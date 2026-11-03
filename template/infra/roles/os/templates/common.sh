if [ -n "${BASH_VERSION-}" ] && [[ $- == *i* ]] && shopt -q login_shell 2>/dev/null; then
    PROMPT_COMMAND="history -a;$PROMPT_COMMAND"
    HISTTIMEFORMAT="%F %T: "
    alias diff='diff --color=auto'
    case "$TERM" in
        xterm-color|*-256color) color_prompt=yes;;
    esac

    export BLOCK_SIZE="'1"
    export TIME_STYLE=long-iso
fi
