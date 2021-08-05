Keycloak CIBA test environment deployer  
=====  
  
  
### Presentation  
  
These scripts were made in order to easily create a test environment for OpenID Connect CIBA on Keycloak.  
While everything should theoretically both deploy and run correctly on any Linux system as long as dependencies are satisfied, nothing has been tested outside of my work environement (Ubuntu 20.04 LTS via WSL) and personal computer (Manjaro). As such, proceeding with some caution might make sense.  
  
/!\ Please note that exposing the environment set up by these scripts on Internet would be extremely unsafe. Keep everything local until you are absolutely sure of what you are doing.  
  

### Dependencies  
  
- Curl  
- Git  
- Maven  
- OpenBSD Netcat (only required for "ping" mode)  
- OpenJDK 8  
- Tmux  
- XDG-Utils  
  
Debian-based distros:  
`# apt install curl git maven openjdk-8-jdk tmux xdg-utils`  
  
Arch-based distros:  
`# pacman -S curl git jdk8-openjdk maven tmux xdg-utils`  
  
Using a JDK whose version is greater than 8 should be fine more often than not, however this is the one Keycloak is intended to be built with.  

  
### Use  
  
deploy.sh is the main script, which works as follow:  
- Clone Keycloak from its main repository (keycloak/Keycloak)  
- Clone the authentication server (tnorimat/ciba-authn-entity)  
- Build both of these  
- Do some configuration in order to enable CIBA  
- Launch Keycloak in order to do some more configuration  
- Start the next script  
  
More information can be found within the file itself.  
  
launch.sh will be executed at the end of deploy.sh and can be manually used thereafter. In accordance to its name, this script launches what has been built through a terminal multiplexer (namely Tmux).  
  
client.sh is a simple script meant to emulate an application that has to authenticate using CIBA. The previously used script will prompt you to execute it once ready.  
Either "poll" (default) or "ping" can be selected as a token delivery mode by passing your choice as an argument, e.g. `$ ./client.sh ping`.  


### Credentials

WildFly (localhost:9990): `Admin:test123!`  
Keycloak (localhost:8080): `Admin:test123!`  
Client #1 ("poll" mode, on realm "ciba"): `client-poll:932cf37e-2dcd-43e5-a990-1dc7a5c1575a`  
Client #2 ("ping" mode, on realm" ciba"): `client-ping:eda67416-42e3-44b7-898c-9ebf7d24cb7f`  
