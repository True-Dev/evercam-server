defmodule EvercamMedia.LogController do
  use EvercamMedia.Web, :controller
  import EvercamMedia.Validation.Log
  import Ecto.Query
  alias EvercamMedia.ErrorView
  alias EvercamMedia.LogView
  alias EvercamMedia.SnapshotRepo
  use Calendar
  import String, only: [to_integer: 1]

  @default_limit 50

  def show(conn, %{"id" => exid} = params) do
    current_user = conn.assigns[:current_user]
    camera = Camera.by_exid_with_associations(exid)

    with :ok <- ensure_camera_exists(camera, exid, conn),
         :ok <- ensure_can_edit(current_user, camera, conn),
         :ok <- validate_params(params) |> ensure_params(conn)
    do
      show_logs(params, camera, conn)
    end
  end

  defp ensure_camera_exists(nil, exid, conn) do
    conn
    |> put_status(404)
    |> render(ErrorView, "error.json", %{message: "Camera '#{exid}' not found!"})
  end
  defp ensure_camera_exists(_camera, _id, _conn), do: :ok

  defp ensure_can_edit(current_user, camera, conn) do
    if current_user && Permission.Camera.can_edit?(current_user, camera) do
      :ok
    else
      conn |> put_status(401) |> render(ErrorView, "error.json", %{message: "Unauthorized."})
    end
  end

  defp show_logs(params, camera, conn) do
    from = parse_from(params["from"])
    to = parse_to(params["to"])
    limit = parse_limit(params["limit"])
    page = parse_page(params["page"])
    types = parse_types(params["types"])

    activities_query =
      CameraActivity
      |> where(camera_id: ^camera.id)
      |> where([c], c.done_at >= ^from and c.done_at <= ^to)
      |> with_types_if_specified(types)

    total_pages =
      from(c in activities_query)
      |> select([c], count(c.id))
      |> SnapshotRepo.one
      |> Kernel./(limit)
      |> Float.floor

    logs =
      activities_query
      |> order_by([c], desc: c.done_at)
      |> limit(^limit)
      |> offset(^(page * limit))
      |> SnapshotRepo.all

    conn
    |> put_status(200)
    |> render(LogView, "show.json", %{total_pages: total_pages, camera_exid: camera.exid, camera_name: camera.name, logs: logs})
  end

  defp parse_to(to) when to in [nil, ""], do: DateTime.now_utc |> DateTime.to_erl
  defp parse_to(to), do: to |> DateTime.Parse.unix! |> DateTime.to_erl

  defp parse_from(from) when from in [nil, ""], do: Ecto.DateTime.cast!("2014-01-01T14:00:00Z") |> Ecto.DateTime.to_erl
  defp parse_from(from), do: from |> DateTime.Parse.unix! |> DateTime.to_erl

  defp parse_limit(limit) when limit in [nil, ""], do: @default_limit
  defp parse_limit(limit), do: if to_integer(limit) < 1, do: @default_limit, else: to_integer(limit)

  defp parse_page(page) when page in [nil, ""], do: 0
  defp parse_page(page), do: if to_integer(page) < 0, do: 0, else: to_integer(page)

  defp parse_types(types) when types in [nil, ""], do: nil
  defp parse_types(types), do: types |> String.split(",", trim: true) |> Enum.map(&String.strip/1)

  defp ensure_params(:ok, _conn), do: :ok
  defp ensure_params({:invalid, message}, conn), do: conn |> put_status(400) |> render(ErrorView, "error.json", %{message: message})

  defp with_types_if_specified(query, nil) do
    query
  end
  defp with_types_if_specified(query, types) do
    query
    |> where([c], c.action in ^types)
  end
end