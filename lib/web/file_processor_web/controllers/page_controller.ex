defmodule FileProcessorWeb.PageController do
  use FileProcessorWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
