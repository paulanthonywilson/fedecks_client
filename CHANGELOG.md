# Change Log

# v0.1.0

Documentation light initial version, pushed up early for Elixir Conf EU Lightning Talks.

# v0.1.1

More documentation 

# v0.1.2

Change of behaviour on receiving errors during connection upgrade. Previously Fedecks assumed an urecoverable fault; now the connector restarts and tries again. It could be a routing issue causing a 404 or a server side issue which could get resolved.


# v0.1.3

Restarts the connection if a pong is not received in response to a ping, within 30 seconds.