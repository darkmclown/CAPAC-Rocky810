invoke_bootstrap() {
  log_section "Bootstrap Loader Menu"

  echo ""
  echo "Repository is ready at:"
  echo "  ${WORKDIR}"
  echo ""
  echo "What do you want to do?"
  echo ""
  echo "  1) Start bootstrap menu"
  echo "     Opens bootstrap.sh and lets you choose automated/manual/validation."
  echo ""
  echo "  2) Run validation only"
  echo "     Runs validate.sh without installing or changing packages."
  echo ""
  echo "  3) Exit"
  echo "     Repo is cloned/updated, but nothing else will run."
  echo ""

  while true; do
    read -rp "Enter choice [1/2/3]: " loader_choice

    case "${loader_choice}" in
      1)
        log_info "Starting bootstrap controller..."
        exec bash "${BOOTSTRAP_SCRIPT}"
        ;;

      2)
        log_info "Running validation only..."
        exec bash "${WORKDIR}/bootstrap/validate.sh"
        ;;

      3)
        log_info "Exiting loader. No bootstrap process started."
        log_info "You can start later with:"
        log_info "  sudo bash ${BOOTSTRAP_SCRIPT}"
        exit 0
        ;;

      *)
        echo "Invalid choice. Please enter 1, 2, or 3."
        ;;
    esac
  done
}