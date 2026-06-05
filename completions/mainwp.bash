# Bash completion for mainwp
# Source this file in your shell: source <(mainwp completion bash)

_mainwp_completions() {
  local cur prev words cword
  _init_completion || return

  local commands="init deps skill config sites clients tags updates costs users settings monitoring api-keys posts pages batch completion help"

  if [[ ${cword} -eq 1 ]]; then
    if [[ ${cur} == -* ]]; then
      COMPREPLY=($(compgen -W "--profile --json --plain --no-input --quiet --version --help" -- "${cur}"))
    else
      COMPREPLY=($(compgen -W "${commands}" -- "${cur}"))
    fi
    return 0
  fi

  local command="${words[1]}"
  case "${command}" in
    sites)
      COMPREPLY=($(compgen -W "list basic count get security non-mainwp-changes client costs plugins themes add edit sync reconnect disconnect check suspend unsuspend remove plugin theme" -- "${cur}"))
      ;;
    clients)
      COMPREPLY=($(compgen -W "list count get add edit remove suspend unsuspend sites sites-count costs fields" -- "${cur}"))
      ;;
    tags)
      COMPREPLY=($(compgen -W "list get add edit remove sites clients" -- "${cur}"))
      ;;
    updates)
      COMPREPLY=($(compgen -W "list for-site ignored site-ignored run-all run-site wp plugins themes translations ignore-wp ignore-plugins ignore-themes" -- "${cur}"))
      ;;
    costs)
      COMPREPLY=($(compgen -W "list get add edit remove sites clients" -- "${cur}"))
      ;;
    users)
      COMPREPLY=($(compgen -W "list create edit delete update-admin-password import" -- "${cur}"))
      ;;
    settings)
      COMPREPLY=($(compgen -W "general advanced monitoring emails cost-tracker insights api-backups tools" -- "${cur}"))
      ;;
    monitoring)
      COMPREPLY=($(compgen -W "list basic count get heartbeat incidents incidents-count check settings global-settings" -- "${cur}"))
      ;;
    api-keys)
      COMPREPLY=($(compgen -W "list add edit delete" -- "${cur}"))
      ;;
    posts)
      COMPREPLY=($(compgen -W "list get create edit update-status delete" -- "${cur}"))
      ;;
    pages)
      COMPREPLY=($(compgen -W "list get create edit update-status delete" -- "${cur}"))
      ;;
    config)
      COMPREPLY=($(compgen -W "get set profile path" -- "${cur}"))
      ;;
    deps)
      COMPREPLY=($(compgen -W "status install" -- "${cur}"))
      ;;
    skill)
      COMPREPLY=($(compgen -W "install" -- "${cur}"))
      ;;
    completion)
      COMPREPLY=($(compgen -W "bash zsh" -- "${cur}"))
      ;;
  esac
}

complete -F _mainwp_completions mainwp
