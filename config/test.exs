use Mix.Config

config :logger, level: :warn

config :ex_fix,
  dictionary_map: [session1: "./test/support/simple_dictionary.xml"],
  logout_timeout: 20