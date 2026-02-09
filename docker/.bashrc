# Bash configuration for OpenClaw container

# Set a colorful prompt showing user@container:path
PS1='\[\033[01;32m\]\u@openclaw\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# Enable color support
if [ -x /usr/bin/dircolors ]; then
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
fi

# Useful aliases
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'

# Command history settings
export HISTSIZE=1000
export HISTFILESIZE=2000
export HISTCONTROL=ignoredups:erasedups

# Make bash check window size after each command
shopt -s checkwinsize
