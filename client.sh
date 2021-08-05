#!/bin/bash


# CIBA client script
# Compatible with bash only due to its 'read' command specificities


declare -A params_hmap # cURL parameters as an associative array
separator="------------------------------"


token_delivery_mode="${1:-poll}"
if [ "${token_delivery_mode}" != 'poll' ] &&
   [ "${token_delivery_mode}" != 'ping' ]; then
    echo 'Invalid token delivery mode (must be either poll or ping)' >&2
    exit 1
fi

if [ "${token_delivery_mode}" = "ping" ] && [ ! -x "$(command -v nc)" ]; then
    echo 'Netcat (NC) BSD version (usually the default) is required for ping mode' >&2
    exit 2
fi


_hmap_parse () {
    local params=""
    for key in ${!params_hmap[@]}; do
        if [ ! -z "${params_hmap[${key}]}" ]; then
            [ -z "${params}" ] || params="${params}&"
            params="${params}$key=${params_hmap[${key}]}"
        fi
    done
    echo "${params}"
}

_print_req_info () {
    echo "----- $1 -----"
    echo "URL: $2"

    if [ ! -z "${authz_header}" ]; then
        echo 'Headers:'
        echo -e "\tAuthorization: ${authz_header}"
    fi

    if [ ! -z "${params}" ]; then
        echo "Form data:"
        for key in ${!params_hmap[@]}; do
            if [ ! -z "${params_hmap[${key}]}" ]; then
                echo -e "\t${key} -> ${params_hmap[${key}]}"
            fi
        done
    fi

    echo "${separator}"
}

_do_curl_req () {
    if [ ! -z "${params}" ]; then
        local res=$(curl -ss -H "Authorization: $2" -d "${params}" "$1")
    else
        local res=$(curl -ss -H "Authorization: $2" "$1")
    fi
    local ret_code=$?

    if [ ${ret_code} -ne 0 ]; then
        echo "Got return code ${ret_code}: something went wrong" >&2
        exit 3
    else
        echo "$3" >/dev/tty # That was pretty annoying to find out
    fi

    echo "${res}"
}

_print_json_resp () {
    read -rn 1 -p 'Display Json results? [y/N] '
    echo # Newline after input
    [[ "${REPLY}" == [yY] ]] && echo "$1" | python -m json.tool
}

_json_parse () {
    [ -z "$1" ] ||
    echo "$1" | python -c 'import sys,json;print(json.load(sys.stdin).get("'$2'", ""))'
}


base_url='http://localhost:8080/auth/realms/ciba/protocol/openid-connect/'
# Endpoint in outdated version: /backchannelAuthn
authn_endpoint="${base_url}ext/ciba/auth"

case "${token_delivery_mode}" in
    # Token delivery in poll mode (default)
    'poll')
        client_id='client-poll' # Keycloak -> Clients (must be set to "confidential")
        client_secret='932cf37e-2dcd-43e5-a990-1dc7a5c1575a'
        ;;

    # Token delivery in ping mode
    'ping')
        client_id='client-ping'
        client_secret='eda67416-42e3-44b7-898c-9ebf7d24cb7f'
        client_notification_token='super-secure-token'
        ;;
esac

login_hint='user001' # Keycloak -> Users (can use either username or email)
scope='openid profile email' # Can be set to anything at the moment
binding_message='hello' # Should be shown on both authentication and consumption devices

# Authorization header
authz_header='Basic '$(echo -n "${client_id}:${client_secret}" | base64 -w 0)


# 1. Backchannel authentication request
params_hmap=(["login_hint"]="${login_hint}" ["scope"]="${scope}"
             ["binding_message"]="${binding_message}"
             ["client_notification_token"]="${client_notification_token}")
params=$(_hmap_parse)
_print_req_info 'Authentication request' "${authn_endpoint}"

authn_res=$(_do_curl_req "${authn_endpoint}" "${authz_header}" \
                         'Authentication request sent')
_print_json_resp "${authn_res}"

auth_req_id=$(_json_parse "${authn_res}" 'auth_req_id')
auth_limit=$(($(date +'%s') + $(_json_parse "${authn_res}" 'expires_in')))
interval=$(_json_parse "${authn_res}" 'interval') # Throttling

if [ -z "${auth_req_id}" ]; then
    echo 'No authentication request ID obtained: is the server up?' >&2
    exit 4
fi


# 2. a. Poll mode - wait for [interval] seconds
if [ "${token_delivery_mode}" = 'poll' ]; then
    echo 'Token delivery mode: poll'

    if [ ! -z "${interval}" ]; then
        sleep_time=$((interval + 5))
        echo "Interval is ${interval}s. Let's sleep for ${sleep_time}s..." >&2
        sleep ${sleep_time}
    else
        sleep_time=2
    fi
fi


# 2. b. Ping mode - wait for token notification
if [ "${token_delivery_mode}" = 'ping' ]; then
    echo 'Token delivery mode: ping'

    echo 'Waiting for a notification on endpoint http://localhost:8081/token-notification'
    # Will answer "OK" BEFORE verifying whether or not the notification is legitimate
    # In the case it isn't, the authentication process as a whole is thereafter interrupted
    # While simple and efficient enough for a proof of concept, this is obviously NOT
    # how it should be done in a production environment...
    ping_res=$(echo -e 'HTTP/1.1 200 OK\r\n' | nc -Nlnp 8081 -s 127.0.0.1 -w 30)

    if [ -z "${ping_res}" ]; then
        echo "Notification hasn't been received within 30 seconds" >&2
        exit 5
    fi

    check_auth_req_id=$(_json_parse $(echo "${ping_res}" | grep 'auth_req_id') 'auth_req_id')
    check_notification_token=$(echo "${ping_res}" | grep 'Authorization' |
                               cut -d ' ' -f 3 | tr -d '\r')

    echo 'Notification received'
    read -rn 1 -p 'Display notification details? [y/N] '
    [[ "${REPLY}" == [yY] ]] && echo -e "\n${separator}\n${ping_res}\n${separator}"

    if [ "${auth_req_id}" != "${check_auth_req_id}" ]; then
        echo "auth_req_id doesn't match" >&2
        exit 6
    elif [ "${client_notification_token}" != "${check_notification_token}" ]; then
        echo "client_notification_token doesn't match" >&2
        exit 7
    fi
fi


# 3. Token retrieval
token_endpoint="${base_url}token"
grant_type='urn:openid:params:grant-type:ciba' # Constant
params_hmap=(["grant_type"]="${grant_type}" ["auth_req_id"]="${auth_req_id}")
params=$(_hmap_parse)
_print_req_info 'Token request' "${token_endpoint}"

while [ $(date +'%s') -lt ${auth_limit} ]; do
    token_res=$(_do_curl_req "${token_endpoint}" "${authz_header}" 'Token request sent')
    _print_json_resp "${token_res}"

    error=$(_json_parse "${token_res}" 'error')
    if [ ! -z "${error}" ]; then
        error_desc=$(_json_parse "${token_res}" 'error_description')
        case "${error}" in
            'slow_down') # Should probably never happen in ping mode?
                sleep_time=$((sleep_time + 5))
                ;&
            'authorization_pending')
                echo -e "Got: ${error_desc}\nLet's sleep for ${sleep_time}s..." >&2
                sleep ${sleep_time}
                continue
                ;;
            'unauthorized_client')
                echo "Unauthorized client: ${error_desc}" >&2
                exit 8
                ;;
            'access_denied')
                echo "Access was denied: ${error_desc}" >&2
                exit 9
                ;;
            'invalid_grant'|'unsupported_grant_type')
                echo "An error occurred: ${error_desc}" >&2
                exit 10
                ;;
            'invalid_request')
                echo "Invalid request: ${error_desc}" >&2
                exit 11
                ;;
            *)
                echo "Unknown error: ${error} (${error_desc})" >&2
                exit 12
                ;;
        esac
    else
        token=$(_json_parse "${token_res}" 'access_token')
        if [ ! -z "${token}" ]; then
            echo 'Token acquired: authentication was successful!'
            break
        else
            echo 'No error, yet no token either... this is definitely not normal' >&2
            exit 13
        fi
    fi
done

if [ -z "${token}" ]; then
    echo 'Time limit exceeded: authentication request has expired' >&2 &&
    exit 14
fi


# 4. UserInfo retrieval
info_endpoint="${base_url}userinfo"
authz_header="Bearer ${token}"
unset params
_print_req_info 'UserInfo request' "${info_endpoint}"

info_res=$(_do_curl_req "${info_endpoint}" "${authz_header}" 'UserInfo request sent')
_print_json_resp "${info_res}"

error=$(_json_parse "${info_res}" 'error')
if [ ! -z "${error}" ]; then
    error_desc=$(_json_parse "${info_res}" 'error_description')
    echo "An error occurred: ${error_desc}" >&2
    exit 15
fi

echo 'User information retrieved; everything went fine'
