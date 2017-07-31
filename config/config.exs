use Mix.Config

config :ex_fix,
  default_dictionary: ExFix.DefaultDictionary,
  logout_timeout: 2_000

import_config "#{Mix.env}.exs"