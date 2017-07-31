use Mix.Config

config :ex_fix,
  session_registry: ExFix.DefaultSessionRegistry,
  default_dictionary: ExFix.DefaultDictionary,
  logout_timeout: 2_000

import_config "#{Mix.env}.exs"