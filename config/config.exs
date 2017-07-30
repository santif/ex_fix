use Mix.Config

config :ex_fix,
  default_fix_application: ExFix.DefaultFixApplication,
  default_dictionary: ExFix.DefaultDictionary

import_config "#{Mix.env}.exs"