defmodule Cloudex.CloudinaryApi do
  @moduledoc """
  The live API implementation for Cloudinary uploading
  """

  alias Cloudex.Telemetry

  @base_url "https://api.cloudinary.com/v1_1/"
  @cloudinary_headers [
    {"Content-Type", "application/x-www-form-urlencoded"},
    {"Accept", "application/json"}
  ]

  @json_library Application.get_env(:cloudex, :json_library, Jason)

  @doc """
  Upload either a file or url to cloudinary
  `opts` can contain:
    %{resource_type: "video"}
  which will cause a video upload to occur.
  returns {:ok, %UploadedFile{}} containing all the information from cloudinary
  or {:error, "reason"}
  """
  @spec upload(String.t() | {:ok, String.t()}, map) ::
          {:ok, Cloudex.UploadedImage.t()} | {:ok, %Cloudex.UploadedVideo{}} | {:error, any}
  def upload(item, opts \\ %{})
  def upload({:ok, item}, opts) when is_binary(item), do: upload(item, opts)

  def upload(item, opts) when is_binary(item) do
    case item do
      "http://" <> _rest -> upload_url(item, opts)
      "https://" <> _rest -> upload_url(item, opts)
      "s3://" <> _rest -> upload_url(item, opts)
      _ -> upload_file(item, opts)
    end
  end

  def upload(invalid_item, _opts) do
    {
      :error,
      "Upload/1 only accepts a String.t or {:ok, String.t}, received: #{inspect(invalid_item)}"
    }
  end

  def upload_large(item, chunk_size \\ 6_000_000, opts \\ %{}) do
    unique_id = Base.encode64(item)
    %{size: size} = File.stat!(item)
    start_time = Telemetry.start(:upload_large)

    case upload_chunks(item, chunk_size, size, unique_id, opts) do
      {:ok, raw_response} ->
        Telemetry.stop(:upload_large, start_time)
        response = @json_library.decode!(raw_response.body)
        handle_response(response, item)

      {:error, raw_response} ->
        Telemetry.stop(:upload_large, start_time)
        error_response = @json_library.decode!(raw_response.body)
        handle_response(%{"error" => %{"message" => error_response}}, item)

      _ ->
        Telemetry.stop(:upload_large, start_time)
        handle_response(%{"error" => %{"message" => "Error uploading file"}}, item)
    end
  end

  defp upload_chunks(item, chunk_size, size, unique_id, opts) do
    File.stream!(item, [], chunk_size)
    |> Stream.with_index()
    |> Enum.reduce_while({:ok, %{}}, fn {chunk, index} = _chunk_with_index, _acc ->
      start_time = Telemetry.start(:chunk)
      content_range = generate_content_range(index, size, chunk_size)
      chunk_resp = upload_chunk(chunk, content_range, unique_id, opts)
      Telemetry.stop(:chunk, start_time)

      case chunk_resp do
        {:ok, %HTTPoison.Response{status_code: 200} = resp} ->
          {:cont, {:ok, resp}}

        {:ok, resp} ->
          {:halt, {:error, resp}}

        {:error, error} ->
          {:halt, error}
      end
    end)
  end

  def upload_chunk(
        chunk,
        content_range,
        unique_id,
        opts
      ) do
    chunk_headers = [
      {"X-Unique-Upload-Id", unique_id},
      {"Content-Range", content_range},
      {"Content-Type", "multipart/form-data"}
    ]

    options = prepare_signed_opts(opts)

    form =
      {:multipart,
       [
         {"file", chunk, {"form-data", [{"name", "file"}, {"filename", "blob"}]},
          [{"content-type", "application/octet-stream"}]}
         | options
       ]}

    url =
      "#{@base_url}#{Cloudex.Settings.get(:cloud_name)}/#{Map.get(opts, :resource_type, "image")}/upload"

    request_options = opts[:request_options] || []

    HTTPoison.post(
      url,
      form,
      chunk_headers,
      credentials() ++ request_options
    )
  end

  defp generate_content_range(index, size, chunk_size) do
    start_byte = index * chunk_size

    end_byte = if div(size, chunk_size) == index, do: size - 1, else: start_byte + chunk_size - 1

    "bytes #{start_byte}-#{end_byte}/#{size}"
  end

  @doc """
  Deletes an image given a public id
  """
  @spec delete(String.t(), map) :: {:ok, %Cloudex.DeletedImage{}} | {:error, any}
  def delete(item, opts \\ %{})

  def delete(item, opts) when is_bitstring(item) do
    case delete_file(item, opts) do
      {:ok, response} -> {:ok, %Cloudex.DeletedImage{public_id: item, response: response}}
      error -> error
    end
  end

  def delete(invalid_item, _opts) do
    {:error, "delete/1 only accepts valid public id, received: #{inspect(invalid_item)}"}
  end

  @doc """
  Deletes images given their prefix
  """
  @spec delete_prefix(String.t(), map) :: {:ok, String.t()} | {:error, any}
  def delete_prefix(prefix, opts \\ %{})

  def delete_prefix(prefix, opts) when is_bitstring(prefix) do
    case delete_by_prefix(prefix, opts) do
      {:ok, _} -> {:ok, prefix}
      error -> error
    end
  end

  def delete_prefix(invalid_prefix, _opts) do
    {:error, "delete_prefix/1 only accepts a valid prefix, received: #{inspect(invalid_prefix)}"}
  end

  @doc """
    Converts the json result from cloudinary to a %UploadedImage{} struct
  """
  @spec json_result_to_struct(map, String.t()) ::
          %Cloudex.UploadedImage{} | %Cloudex.UploadedVideo{}
  def json_result_to_struct(result, source) do
    converted = Enum.map(result, fn {k, v} -> {String.to_atom(k), v} end) ++ [source: source]

    if result["resource_type"] == "video" do
      struct(%Cloudex.UploadedVideo{}, converted)
    else
      struct(%Cloudex.UploadedImage{}, converted)
    end
  end

  @spec upload_file(String.t(), map) ::
          {:ok, %Cloudex.UploadedImage{}} | {:ok, %Cloudex.UploadedVideo{}} | {:error, any}
  defp upload_file(file_path, opts) do
    options = prepare_signed_opts(opts)

    body = {:multipart, [{:file, file_path} | options]}
    post(body, file_path, opts)
  end

  @spec extract_cloudinary_opts(map) :: map
  defp extract_cloudinary_opts(opts) do
    Map.delete(opts, :resource_type)
  end

  @spec upload_url(String.t(), map) ::
          {:ok, %Cloudex.UploadedImage{}} | {:ok, %Cloudex.UploadedVideo{}} | {:error, any}
  defp upload_url(url, opts) do
    opts
    |> Map.delete(:request_options)
    |> Map.merge(%{file: url})
    |> prepare_opts
    |> sign
    |> URI.encode_query()
    |> post(url, opts)
  end

  defp credentials do
    [
      hackney: [
        basic_auth: {Cloudex.Settings.get(:api_key), Cloudex.Settings.get(:secret)}
      ]
    ]
  end

  @spec delete_file(bitstring, map) ::
          {:ok, HTTPoison.Response.t() | HTTPoison.AsyncResponse.t()}
          | {:error, HTTPoison.Error.t()}
  defp delete_file(item, opts) do
    {request_opts, opts} = Map.pop(opts, :request_options, [])

    HTTPoison.delete(
      delete_url_for(opts, item),
      @cloudinary_headers,
      credentials() ++ request_opts
    )
  end

  defp delete_url_for(opts, item) do
    "#{@base_url}#{Cloudex.Settings.get(:cloud_name)}/resources/#{
      Map.get(opts, :resource_type, "image")
    }/#{Map.get(opts, :type, "upload")}?public_ids[]=#{item}"
  end

  @spec delete_file(bitstring, map) ::
          {:ok, HTTPoison.Response.t() | HTTPoison.AsyncResponse.t()}
          | {:error, HTTPoison.Error.t()}
  defp delete_by_prefix(prefix, opts) do
    {request_opts, opts} = Map.pop(opts, :request_options, [])

    HTTPoison.delete(
      delete_prefix_url_for(opts, prefix),
      @cloudinary_headers,
      credentials() ++ request_opts
    )
  end

  defp delete_prefix_url_for(%{resource_type: resource_type}, prefix) do
    delete_prefix_url(resource_type, prefix)
  end

  defp delete_prefix_url_for(_, prefix), do: delete_prefix_url("image", prefix)

  defp delete_prefix_url(resource_type, prefix) do
    "#{@base_url}#{Cloudex.Settings.get(:cloud_name)}/resources/#{resource_type}/upload?prefix=#{
      prefix
    }"
  end

  @spec post(tuple | String.t(), binary, map) ::
          {:ok, %Cloudex.UploadedImage{}} | {:ok, %Cloudex.UploadedVideo{}} | {:error, any}
  defp post(body, source, opts) do
    with {:ok, raw_response} <- common_post(body, opts),
         {:ok, response} <- @json_library.decode(raw_response.body),
         do: handle_response(response, source)
  end

  defp common_post(body, opts) do
    {request_opts, opts} = Map.pop(opts, :request_options, [])

    HTTPoison.request(
      :post,
      url_for(opts),
      body,
      @cloudinary_headers,
      credentials() ++ request_opts
    )
  end

  defp context_to_list(context) do
    context
    |> Enum.reduce([], fn {k, v}, acc -> acc ++ ["#{k}=#{v}"] end)
    |> Enum.join("|")
  end

  @spec prepare_opts(map | list) :: map

  defp prepare_opts(%{tags: tags} = opts) when is_list(tags),
    do: %{opts | tags: Enum.join(tags, ",")} |> prepare_opts()

  defp prepare_opts(%{context: context} = opts) when is_map(context),
    do: %{opts | context: context_to_list(context)} |> prepare_opts()

  defp prepare_opts(opts), do: opts

  defp prepare_signed_opts(opts) do
    opts
    |> Map.delete(:request_options)
    |> extract_cloudinary_opts
    |> prepare_opts
    |> sign
    |> unify
    |> Map.to_list()
  end

  defp url_for(%{resource_type: resource_type}), do: url(resource_type)
  defp url_for(_), do: url("image")

  def url(resource_type) do
    "#{@base_url}#{Cloudex.Settings.get(:cloud_name)}/#{resource_type}/upload"
  end

  @spec handle_response(map, String.t()) ::
          {:error, any} | {:ok, %Cloudex.UploadedImage{}} | {:ok, %Cloudex.UploadedVideo{}}
  defp handle_response(
         %{
           "error" => %{
             "message" => error
           }
         },
         _source
       ) do
    {:error, error}
  end

  defp handle_response(response, source) do
    {:ok, json_result_to_struct(response, source)}
  end

  #  Unifies hybrid map into string-only key map.
  #  ie. `%{a: 1, "b" => 2} => %{"a" => 1, "b" => 2}`
  @spec unify(map) :: map
  defp unify(data), do: Enum.reduce(data, %{}, fn {k, v}, acc -> Map.put(acc, "#{k}", v) end)

  @spec sign(map) :: map
  def sign(data) do
    timestamp = current_time()

    data_without_secret =
      data
      |> Map.drop([:file, :resource_type])
      |> Map.merge(%{"timestamp" => timestamp})
      |> Enum.map(fn {key, val} -> "#{key}=#{val}" end)
      |> Enum.sort()
      |> Enum.join("&")

    signature = sha(data_without_secret <> Cloudex.Settings.get(:secret))

    Map.merge(
      data,
      %{
        "timestamp" => timestamp,
        "signature" => signature,
        "api_key" => Cloudex.Settings.get(:api_key)
      }
    )
  end

  @spec sha(String.t()) :: String.t()
  defp sha(query) do
    :sha
    |> :crypto.hash(query)
    |> Base.encode16()
    |> String.downcase()
  end

  @spec current_time :: String.t()
  defp current_time do
    Timex.now()
    |> Timex.to_unix()
    |> round
    |> Integer.to_string()
  end
end
