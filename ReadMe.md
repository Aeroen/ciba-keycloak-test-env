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
- OpenJDK 8 or later  
- Tmux  
- XDG-Utils  
  
Debian-based distros:  
`# apt install curl git maven openjdk-8-jdk tmux xdg-utils`  
  
Arch-based distros:  
`# pacman -S curl git jdk8-openjdk maven tmux xdg-utils`  

  
### Use  
  
deploy.sh is the main script, which works as follow:  
- Clone Keycloak from its main repository (keycloak/Keycloak)  
- Clone the authentication server (Aeroen/ciba-decoupled-authn-server)  
- Build both of these  
- Do some configuration in order to enable CIBA  
- Launch Keycloak in order to do some more configuration  
- Start the next script  
  
More information can be found within the file itself.  
  
launch.sh will be executed at the end of deploy.sh and can be manually used thereafter. In accordance to its name, this script launches what has been built through a terminal multiplexer (namely Tmux).  
  
client.sh is a simple script meant to emulate an application that has to authenticate using CIBA. The previously used script will prompt you to execute it once ready.  


### Credentials

WildFly (localhost:9990): `Admin:test123!`  
Keycloak (localhost:8080): `Admin:test123!`  
Client (on realm CIBA): `client:932cf37e-2dcd-43e5-a990-1dc7a5c1575a`  
