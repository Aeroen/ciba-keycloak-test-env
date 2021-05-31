Keycloak CIBA test environment deployer  
=====  
  
  
### Presentation  
  
These scripts were made in order to easily create a test environment for OpenID Connect CIBA on Keycloak.  
While everything should theoretically both deploy and run correctly on any Linux system as long as dependencies are satisfied, nothing has been tested outside of my work environement (Ubuntu 20.04 LTS via WSL). As such, proceeding with some caution might make sense.  
  

### Dependencies  
  
- Curl  
- Git  
- Maven  
- OpenJDK 8  
- Tmux  
- XDG-Utils  
  
Debian-based distros:  
`sudo apt install curl git maven openjdk-8-jdk tmux xdg-utils`  
  
Arch-based distros:  
`sudo pacman -S curl git jdk8-openjdk maven tmux xdg-utils`  
  
### Use  
  
  
deploy.sh is the main script, which works as follow:  
- Clone Keycloak from its main repository (keycloak/Keycloak)  
- Clone the authentication server (Aeroen/ciba-decoupled-authn-server)  
- Build both of these  
- Do some configuration in order to enable CIBA  
- Launch Keycloak in order to do some more configuration  
- Start the next script  
More information can be found inside said script.  
  
launch.sh will be executed at the end of deploy.sh and can be manually used thereafter. In accordance to its name, this script launches what has been built through a terminal multiplexer (namely Tmux).  
  
client.sh is a simplistic script meant to emulate an application that has to authenticate using CIBA. The previous script will prompt you to use it once ready.  
