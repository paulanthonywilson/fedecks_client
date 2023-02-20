import Config

if :test == Mix.env() do
  config :fedecks_client, FedecksServerEndpoint,
    http: [ip: {127, 0, 0, 1}, port: 12833],
    server: true,
    live_reload: false

  config :fedecks_client, FedecksTestHandler,
    salt: "f+iKwc1sXyEUcw1zaAZxJCy/VTcSWb83/tNDGNIyw8spS4In53XpJnMvYAgCrI1X",
    secret: "P0bx8wgidqtRCE53Vng1pESXHT9k1OD7HwAnwpAfCHd6La3VPfc+ZLpQRPYbAdqg"
end
