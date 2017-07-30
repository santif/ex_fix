# ExFixInitiator

Example of FIX initiator that sends 10,000 orders to a QuickFIX/J acceptor
over a SSL connection.

## Running

First run QuickFIX/J acceptor; see `examples/quickfixj_acceptor/README.md`.

Then, run initiator:

    $ iex -S mix
    > ExFixInitiatior.start()
