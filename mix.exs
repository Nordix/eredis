defmodule Eredis.Mixfile do
  use Mix.Project

  @source_url "https://github.com/Nordix/eredis/"
  @version "1.3.1-nordix"

  def project do
    [
      app: :eredis,
      deps: deps(),
      description: "Non-blocking Redis client with focus on performance and robustness.",
      elixir: ">= 1.5.1",
      package: package(),
      source_url: @source_url,
      start_permanent: Mix.env() == :prod,
      version: @version
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    []
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    []
  end

  defp package() do
    [
      maintainers: ["Viktor Söderqvist", "Bjorn Svensson"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
