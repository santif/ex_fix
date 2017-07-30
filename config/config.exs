use Mix.Config

config :ex_fix,
  default_dictionary: ExFix.DefaultDictionary

import_config "#{Mix.env}.exs"