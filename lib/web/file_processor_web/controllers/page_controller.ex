defmodule FileProcessorWeb.PageController do
  use FileProcessorWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def procesar(conn, params) do
  IO.inspect(params, label: "PARAMS RECIBIDOS")

  text(conn, "Formulario recibido correctamente")
end
end
