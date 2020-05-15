defmodule Cloudex.Metrics do
  require Logger
  import Telemetry.Metrics

  def setup do
    events = [
      [:cloudex, :upload_large, :success],
      [:cloudex, :upload_chunk, :success],
      [:cloudex, :upload_large, :failure],
      [:cloudex, :upload_chunk, :failure]
    ]
  
    :telemetry.attach_many("cloudex-metrics", events, &handle_event/4, nil)
  end

  def handle_event([:cloudex, :upload_large, :success], measurements, metadata, _config) do
    Logger.info inspect(measurements)
    Logger.info inspect(metadata)
    counter("cloudex.upload_large.success")
    summary("cloudex.upload_large.success")
  end

  def handle_event([:cloudex, :upload_chunk, :success], measurements, metadata, _config) do
    Logger.info inspect(measurements)
    Logger.info inspect(metadata)
    summary("cloudex.upload_chunk.success")
  end

  def handle_event([:cloudex, :upload_large, :failure], measurements, metadata, _config) do
    Logger.info inspect(measurements)
    Logger.info inspect(metadata)
    counter("cloudex.upload_large.failure")
    summary("cloudex.upload_large.failure")
  end

  def handle_event([:cloudex, :upload_chunk, :failure], measurements, metadata, _config) do
    Logger.info inspect(measurements)
    Logger.info inspect(metadata)
    summary("cloudex.upload_chunk.failure")
  end
end