defmodule SyncedState.MixProject do
  use Mix.Project

  @version "0.0.1"
  @url "https://github.com/omginbd/synced_state"

  def project do
    [
      app: :synced_state,
      version: @version,
      elixir: "~> 1.15",
      description: "A macro to sync state changes across liveviews",
      package: package(),
      docs: &docs/0,
      aliases: [docs: &build_docs/1]
    ]
  end

  defp docs do
    [extras: ["README.md", "blogpost.md"]]
  end

  defp package do
    %{
      licenses: ["MIT"],
      maintainers: ["Michael Collier"],
      links: %{
        "GitHub" => @url,
        "Changelog" => "#{@url}/blob/master/CHANGELOG.md"
      }
    }
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp build_docs(_) do
    Mix.Task.run("compile")
    ex_doc = Path.join(Mix.path_for(:escripts), "ex_doc")

    unless File.exists?(ex_doc) do
      raise "cannot build docs because escript for ex_doc is not installed"
    end

    args = ["SyncedState", @version, Mix.Project.compile_path()]
    opts = ~w[--main SyncedState --source-ref v#{@version} --source-url #{@url}]
    System.cmd(ex_doc, args ++ opts)
    Mix.shell().info("Docs built successfully")
  end
end
