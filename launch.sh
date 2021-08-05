#!/bin/bash


# Keycloak CIBA launcher


# Won't go far otherwise...
if [ ! -x "$(command -v tmux)" ]; then
    echo 'Error: tmux not installed' >&2
    exit 1
fi

if [ ! -x "$(command -v xdg-open)" ]; then
    echo 'Error: xdg-open (package: xdg-utils) not installed' >&2
    exit 1
fi

# Keycloak release tag - default is 15.0.0 (currently the latest)
KEYCLOAK_TAG="${1:-15.0.0}"

SESSION='CIBA'
SESSION_EXISTS=$(tmux list-sessions 2>/dev/null | grep "${SESSION}")

# If this variable is set, we're already using Tmux
if [ -z "${TMUX}" ]; then
    # Only create session if it doesn't already exist
    if [ -z "${SESSION_EXISTS}" ]; then

        # Start new session with our name
        tmux new-session -d -s "${SESSION}"

        # Rename first (and only, at the moment) window
        tmux rename-window -t "${SESSION}:0" 'Keycloak'

        # Split the window into three panes
        tmux split-window -t 'Keycloak.0' -h
        tmux split-window -t 'Keycloak.0' -v
        # Uncomment for four panes instead
        #tmux split-window -t 'Keycloak.2' -v

        # Launch keycloak server in first pane...
        tmux send-keys -t 'Keycloak.0' "cd ./keycloak/keycloak-${KEYCLOAK_TAG}/" 'C-m'
        tmux send-keys -t 'Keycloak.0' './bin/standalone.sh --server-config standalone.xml' 'C-m'

        # Launch decoupled authentication server in second pane...
        tmux send-keys -t 'Keycloak.1' 'cd ./authn-server/' 'C-m'
        tmux send-keys -t 'Keycloak.1' 'java -jar ./target/ciba-decoupled-authn-server-0.0.1-SNAPSHOT.war' 'C-m'

        # Lauching the client script before both servers are up wouldn't be bright. How about some Tmux help in the meantime?
        tmux send-keys -t 'Keycloak.2' 'C-l' # Clear the "echo" commands, not their outputs
        tmux send-keys -t 'Keycloak.2' 'echo "Not used to Tmux? This may help: https://tmuxcheatsheet.com"' 'C-m'
        tmux send-keys -t 'Keycloak.2' 'echo "Your web browser is going to open. Don'"'"'t worry! It is used to choose the response you want the authentication server to send."' 'C-m'
        tmux send-keys -t 'Keycloak.2' 'echo -e "<- Once the wall of text stops rolling over there...\n"' 'C-m'
        tmux send-keys -t 'Keycloak.2' './client.sh poll # ... you should be able to press "Enter"!'

        # Select the pane we'll interact with from now on
        tmux select-pane -t 'Keycloak.2'
    fi
else
    echo 'Error: nesting Tmux is a bad idea' >&2
    exit 2
fi

# Finally, attach the session
sleep 15 && xdg-open 'http://localhost:8888/params/' &!
tmux attach-session -t "${SESSION}"
