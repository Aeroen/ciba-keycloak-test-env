#!/bin/sh


# Keycloak CIBA "one click" deployer
# Current status: Working as expected... on my machines


# Enable proxy if necessary
USE_PROXY=false
PROXY_IP=''
PROXY_PORT=''

# Target release version
KEYCLOAK_TAG='13.0.1'


# Preparations
if [ ! -x "$(command -v mvn)" ]; then
    echo 'Error: Maven either not installed or not in PATH' >&2
    exit 1
fi

if [ ! -x "$(command -v git)" ]; then
    echo 'Error: Git either not installed or not in PATH' >&2
    exit 1
fi

if [ -x "$(command -v java)" ]; then
    # Won't work with Oracle's JDK but who uses that anyway?
    version=$(java -version 2>&1 | sed -n 's/^openjdk version "\(1[0-9]*\.[0-9]*\).*$/\1/p')
    if [ ! $(echo "${version} >= 1.8" | bc -l) ]; then
        echo 'Error: OpenJDK >= 8 is required' >&2
        exit 1
    fi
else
    echo 'Error: Java either not installed or not in PATH' >&2
    exit 1
fi

if [ ${USE_PROXY} = true ]; then
    # Using http_proxy like everything else isn't the Maven way of doing things
    if [ ! -d "${HOME}/.m2/" ] || [ ! -f "${HOME}/.m2/settings.xml" ]; then
        mkdir -p "${HOME}/.m2/"
        cat > "${HOME}/.m2/settings.xml" << EoF
<settings>
    <proxies>
        <proxy>
            <id>PROXY</id>
            <active>true</active>
            <protocol>http</protocol>
            <host>${PROXY_IP}</host>
            <port>${PROXY_PORT}</port>
        </proxy>
    </proxies>
</settings>
EoF
    fi

    printf -v MAVEN_OPTS '%s' \
        "-Dhttp.proxyHost=${PROXY_IP} -Dhttp.proxyPort=${PROXY_PORT} " \
        "-Dhttps.proxyHost=${PROXY_IP} -Dhttps.proxyPort=${PROXY_PORT}"
    export MAVEN_OPTS
fi


### First step: download

keycloak_repo_url='https://github.com/keycloak/keycloak'
keycloak_dir='./keycloak/'
authn_server_repo_url='https://github.com/Aeroen/ciba-decoupled-authn-server'
authn_server_dir='./authn-server/'

git clone -q "${keycloak_repo_url}"
[ $? -ne 0 ] && echo 'Error: unable to clone Keycloak from repository' >&2 && exit 3
git -C "${keycloak_dir}" checkout -q "${KEYCLOAK_TAG}"
[ $? -ne 0 ] && echo 'Error: tag '"'${KEYCLOAK_TAG}'"' not found' >&2 && exit 4

git clone -q "${authn_server_repo_url}" && mv './ciba-decoupled-authn-server/' "${authn_server_dir}"
[ $? -ne 0 ] && echo 'Error: unable to clone the authn server from repository' >&2 && exit 3


### Second step: build

if [ -d "${keycloak_dir}" ]; then
    cd "${keycloak_dir}"
    git reset -q --hard
    mvn -q -Pdistribution -pl 'distribution/server-dist' \
        -am -Dmaven.test.skip clean install
    if [ $? -ne 0 ]; then
        echo 'Error: unable to build in '"'${keycloak_dir}'"'' >&2
        exit 7
    fi
else
    echo 'Error: unable to find '"'${keycloak_dir}'"'' >&2
    exit 8
fi

cd -

if [ -d "${authn_server_dir}" ]; then
    cd "${authn_server_dir}"
    git reset -q --hard
    ./mvnw -q clean install -DskipTests
    if [ $? -ne 0 ]; then
        echo 'Error: unable to build in '"'${authn_server_dir}'"'' >&2
        exit 7
    fi
else
    echo 'Error: unable to find '"'${authn_server_dir}'"'' >&2
    exit 8
fi

cd -


### Third step: configure

cd "${keycloak_dir}"
# Avoid cd'ing all over the world
mv "./distribution/server-dist/target/keycloak-${KEYCLOAK_TAG}/" .
cd - && cd "${keycloak_dir}/keycloak-${KEYCLOAK_TAG}/"

# The authn server should be added as an SPI in Keycloak's configuration file
spi=('            <spi name="ciba-auth-channel">
                  <default-provider>ciba-http-auth-channel</default-provider>
                  <provider name="ciba-http-auth-channel" enabled="true">                
                      <properties>
                          <property name="httpAuthenticationChannelUri"
                                    value="http://localhost:8888/request-authentication-channel"/>
                      </properties>
                  </provider>
            </spi>')
target=$(($(grep -n '</spi>' './standalone/configuration/standalone.xml' | tail -1 | cut -d ':' -f 1) + 1))
sed -ie "${target} i $(printf '%q' "${spi}" | sed -e 's/^\$\x27/\\/' -e 's/\x27$//')" \
        './standalone/configuration/standalone.xml'

# Fix for an annoying "bug"
echo 'layers=keycloak' >> './modules/layers.conf'

# Add a WildFly user - not necessary, but why not?
'./bin/add-user.sh' -u 'Admin' -p 'test123!' -e

if [ $? -eq 0 ]; then
    echo 'WildFly user "Admin" added - password is "test123!"'
    echo 'URL: http://localhost:9990'
else
    echo 'Error: unable to add an user in WildFly' >&2
    exit 9
fi

# Add a Keycloak user
'./bin/add-user-keycloak.sh' -u 'Admin' -p 'test123!'

if [ $? -eq 0 ]; then
    echo 'Keycloak user "Admin" added - password is "test123!"'
    echo 'URL: http://localhost:8080/auth'
else
    echo 'Error: unable to add an user in Keycloak' >&2
    exit 10
fi

# Launch WildFly/Keycloak in the background
nohup sh -c './bin/standalone.sh -Dkeycloak.profile.feature.ciba=enabled ' \
            '--server-config standalone.xml' >/dev/null 2>&1 &

# Used later on in order to shut Keycloak down
# Taken from https://unix.stackexchange.com/a/124148
list_descendants () {
    local children=$(ps -o pid= --ppid "$1")

    for pid in $children; do
        list_descendants "$pid"
    done

    echo "$children"
}

# Keycloak must be online for what is to follow
for i in $(seq 1 30); do
    curl -ss 'http://localhost:8080/auth' >/dev/null
    [ $? -eq 0 ] && break
    
    if [ ${i} -eq 30 ]; then
        echo "Error: Keycloak won't start (or is too slow)" >&2
        exit 11
    fi 

    echo 'Keycloak not up yet... sleeping for 5s'
    sleep 5
done

# Login to Keycloak
'./bin/kcadm.sh' config credentials --server 'http://localhost:8080/auth' \
                                    --realm 'master' \
                                    --user 'Admin' \
                                    --password 'test123!'

# Add a new realm named "CIBA"
'./bin/kcadm.sh' create realms -s 'realm=CIBA' -s 'enabled=true'

# Create an user on said realm
'./bin/kcadm.sh' create users -r 'CIBA' -s 'username=user001' \
                                        -s 'email=user001@localhost' \
                                        -s 'firstName=User' \
                                        -s 'lastName=Name' \
                                        -s 'enabled=true' \
                                        -s 'emailVerified=true'

# Create a new client (for the application, in our case client.sh)
'./bin/kcadm.sh' create clients -r 'CIBA' -i -f - << EoF
{
    "clientId": "client",
    "secret": "932cf37e-2dcd-43e5-a990-1dc7a5c1575a",
    "enabled": true,
    "publicClient": false,
    "bearerOnly": false,
    "directAccessGrantsEnabled": true,
    "clientAuthenticatorType": "client-secret",
    "redirectUris": ["*"],
    "attributes": {
        "oidc.ciba.grant.enabled": true
    }
}
EoF

# Once the configuration is done, we'll do a "clean" (re-)launch of everything
kill $(list_descendants $$) 2>/dev/null

cd -


### Fourth step: launch

./launch.sh # Hopefully...
