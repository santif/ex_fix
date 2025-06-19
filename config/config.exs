import Config

config :ex_fix,
  warning_on_garbled_messages: false,
  session_registry: ExFix.DefaultSessionRegistry,
  default_dictionary: ExFix.DefaultDictionary,
  logout_timeout: 2_000

config :elixir, :time_zone_database, Calendar.UTCOnlyTimeZoneDatabase

import_config "#{Mix.env()}.exs"
