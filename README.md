Run this after connected to Coolify

curl -fsSL https://raw.githubusercontent.com/tlun0911/signoz-collector/main/install.sh \\
  | sudo --preserve-env=OTEL_BASIC_AUTH bash
