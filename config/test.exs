use Mix.Config

config :logger, level: :warn

config :ex_fix,
  dictionary_xml: "./test/support/simple_dictionary.xml",
  logout_timeout: 20