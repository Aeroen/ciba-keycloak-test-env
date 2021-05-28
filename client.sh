#!/bin/bash


# CIBA client script
# Compatible with bash only due to its 'read' command specificities
# Todo:
#   - Add a request to the "userinfo" endpoint
#   - Use Authorization (Basic) header instead of POST parameters


declare -A params_hmap # cURL parameters as an associative array

_hmap_parse () {
    local params=""
    for key in ${!params_hmap[@]}; do
        [ -z "${params}" ] || params="${params}&"
        params="${params}$key=${params_hmap[$key]}"
    done
    echo "${params}"
}

_do_curl_req () {
    local res=$(curl -ss -d "${params}" "$1")
    local ret_code=$?

    if [ ${ret_code} -ne 0 ]; then
        echo "Got return code ${ret_code}: something went wrong" >&2
        exit 1
    else
        echo "$2" >/dev/tty # That was pretty annoying to find out 
    fi
    
    echo "${res}"
}

_json_parse () {
    [ -z "$1" ] || echo "$1" | python -c 'import sys,json;print(json.load(sys.stdin).get("'$2'", ""))'
}

base_url='http://localhost:8080/auth/realms/CIBA/protocol/openid-connect/'
# Endpoint in outdated version: /backchannelAuthn
authn_endpoint="${base_url}ext/ciba/auth"

client_id='client' # Keycloak -> Clients (must be set to "confidential")
client_secret='932cf37e-2dcd-43e5-a990-1dc7a5c1575a'
login_hint='user001' # Keycloak -> Users (can use either username or email)
scope='profile email' # Can be set to anything at the moment
binding_message='hello' # Should be shown on both authentication and consumption devices

# 1. Backchannel authentication request
params_hmap=(["client_id"]="${client_id}" ["client_secret"]="${client_secret}"
             ["login_hint"]="${login_hint}" ["scope"]="${scope}"
             ["binding_message"]="${binding_message}") 
params=$(_hmap_parse)

authn_res=$(_do_curl_req "${authn_endpoint}" 'Authentication request sent')

auth_req_id=$(_json_parse "${authn_res}" 'auth_req_id')
auth_limit=$(($(date +'%s') + $(_json_parse "${authn_res}" 'expires_in')))
interval=$(_json_parse "${authn_res}" 'interval') # Throttling

if [ -z "${auth_req_id}" ]; then
    echo 'No authentication request ID obtained: is the server up?' >&2
    exit 2
fi

token_endpoint="${base_url}token"
grant_type='urn:openid:params:grant-type:ciba' # Constant 

# 2. Token request (polling)
params_hmap=(["client_id"]="${client_id}" ["client_secret"]="${client_secret}"
             ["grant_type"]="${grant_type}" ["auth_req_id"]="${auth_req_id}")
params=$(_hmap_parse)

if [ ! -z "${interval}" ]; then
    sleep_time=$((interval + 5))
    echo "Interval is ${interval}s. Let's sleep for ${sleep_time}s..." >&2
    sleep ${sleep_time}
else
    sleep_time=2
fi

while [ $(date +'%s') -lt ${auth_limit} ]; do
    token_res=$(_do_curl_req "${token_endpoint}" 'Token request sent')
    error=$(_json_parse "${token_res}" 'error')
    if [ ! -z "${error}" ]; then
        error_desc=$(_json_parse "${token_res}" 'error_description')
        case "${error}" in
            'slow_down')
                sleep_time=$((sleep_time + 5))
                ;&
            'authorization_pending')
                echo -e "Got: ${error_desc}\nLet's sleep for ${sleep_time}s..." >&2
                sleep ${sleep_time}
                continue
                ;;
            'unauthorized_client')
                echo "Unauthorized client: ${error_desc}" >&2
                exit 3
                ;;
            'access_denied')
                echo "Access was denied: ${error_desc}" >&2
                exit 4
                ;;
            'invalid_grant'|'unsupported_grant_type')
                echo "An error occurred: ${error_desc}" >&2
                exit 5
                ;;
            'invalid_request')
                echo "Invalid request : ${error_desc}" >&2
                exit 6
                ;;
            *)
                echo "Unknown error: ${error} (${error_desc})" >&2
                exit 7
                ;;
        esac
    else
        token=$(_json_parse "${token_res}" 'access_token')
        if [ ! -z "${token}" ]; then
            echo 'Token acquired: authentication was successful!' 
            read -rn 1 -p 'Display Json results? [y/N] '
            echo # Newline after input
            [[ "${REPLY}" == [yY] ]] && echo "${token_res}" | python -m json.tool
            exit 0
        else
            echo 'No error, yet no token either... this should NOT happen' >&2
            exit 8
        fi
    fi
done

echo 'Time limit exceeded: authentication request has expired' >&2
exit 9
