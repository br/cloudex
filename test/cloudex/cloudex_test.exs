defmodule CloudexTest do
  use ExUnit.Case, async: false
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney

  @json_library Application.get_env(:cloudex, :json_library, Jason)

  setup_all do
    ExVCR.Config.cassette_library_dir("test/assets/vcr_cassettes")
    :ok
  end

  doctest Cloudex

  test "file not found" do
    assert {:error, "File /non/existing/file.jpg does not exist."} =
             Cloudex.upload("/non/existing/file.jpg")
  end

  test "upload single image file" do
    use_cassette "test_upload" do
      assert {:ok, %Cloudex.UploadedImage{}} =
               Cloudex.upload("test/assets/test.jpg", %{
                 request_options: [recv_timeout: 60000, max_redirect: 3]
               })
    end
  end

  test "upload single image file with specific recv_timeout" do
    use_cassette "test_upload" do
      assert {:ok, %Cloudex.UploadedImage{}} =
               Cloudex.upload("test/assets/test.jpg", %{
                 request_options: [recv_timeout: 60000, max_redirect: 3]
               })
    end
  end

  test "upload single video file" do
    use_cassette "test_upload_video" do
      result =
        Cloudex.upload("test/assets/teamwork.mp4", %{
          resource_type: "video",
          request_options: [recv_timeout: 60000, max_redirect: 3]
        })

      assert {:ok,
              %Cloudex.UploadedVideo{
                audio: %{},
                bit_rate: 27217,
                bytes: 299_396,
                created_at: "2018-08-27T03:15:42Z",
                duration: 88.0,
                eager: [],
                etag: "aaf7d25e2f37927b2be50e20c58304e3",
                format: "mp4",
                frame_rate: 25.0,
                height: 400,
                original_filename: "teamwork",
                public_id: "bqzkffnaviwjafajqraf",
                resource_type: "video",
                secure_url:
                  "https://res.cloudinary.com/my_cloud_name/video/upload/v1535339742/bqzkffnaviwjafajqraf.mp4",
                signature: "5b477564193de869ad6cf84e561dd74a091a2211",
                source: "test/assets/teamwork.mp4",
                tags: [],
                type: "upload",
                url:
                  "http://res.cloudinary.com/my_cloud_name/video/upload/v1535339742/bqzkffnaviwjafajqraf.mp4",
                version: 1_535_339_742,
                video: %{
                  "bit_rate" => "26340",
                  "codec" => "h264",
                  "dar" => "8:5",
                  "level" => 31,
                  "pix_format" => "yuv420p",
                  "profile" => "Constrained Baseline"
                },
                width: 640
              }} = result
    end
  end

  test "upload multiple image files" do
    use_cassette "multi_upload" do
      assert [
               {:ok, %Cloudex.UploadedImage{}},
               {:ok, %Cloudex.UploadedImage{}},
               {:ok, %Cloudex.UploadedImage{}}
             ] =
               Cloudex.upload("test/assets/multiple", %{
                 request_options: [recv_timeout: 60000, max_redirect: 3]
               })
    end
  end

  test "upload image url" do
    use_cassette "test_upload_url with both http and https" do
      assert {:ok, %Cloudex.UploadedImage{}} =
               Cloudex.upload(
                 "http://cdn.mhpbooks.com/uploads/2014/10/shutterstock_172896005.jpg",
                 %{request_options: [recv_timeout: 60000, max_redirect: 3]}
               )

      assert {:ok, %Cloudex.UploadedImage{}} =
               Cloudex.upload(
                 "https://cdn.mhpbooks.com/uploads/2014/10/shutterstock_172896005.jpg",
                 %{request_options: [recv_timeout: 60000, max_redirect: 3]}
               )
    end
  end

  test "upload s3 image url" do
    use_cassette "test_upload_url with s3" do
      assert {:ok, %Cloudex.UploadedImage{}} =
               Cloudex.upload("s3://my-bucket/folder/test_image.jpg", %{
                 request_options: [recv_timeout: 60000, max_redirect: 3]
               })
    end
  end

  test "mixed files / urls" do
    use_cassette "test_upload_mixed" do
      assert [
               {:ok, %Cloudex.UploadedImage{}},
               {:ok, %Cloudex.UploadedImage{}},
               {:error, "File nonexistent.png does not exist."}
             ] =
               Cloudex.upload(
                 [
                   "./test/assets/test.jpg",
                   "nonexistent.png",
                   "https://cdn.mhpbooks.com/uploads/2014/10/shutterstock_172896005.jpg"
                 ],
                 %{request_options: [recv_timeout: 60000, max_redirect: 3]}
               )
    end
  end

  test "upload with tags" do
    use_cassette "test_upload_with_tags" do
      tags = ["foo", "bar"]

      {:ok, %Cloudex.UploadedImage{tags: ^tags}} =
        Cloudex.upload(["./test/assets/test.jpg"], %{
          tags: Enum.join(tags, ","),
          request_options: [recv_timeout: 60000, max_redirect: 3]
        })

      # or simply
      {:ok, %Cloudex.UploadedImage{tags: ^tags}} =
        Cloudex.upload(["./test/assets/test.jpg"], %{
          tags: tags,
          request_options: [recv_timeout: 60000, max_redirect: 3]
        })
    end
  end

  test "upload with phash" do
    use_cassette "test_upload_with_phash" do
      {:ok, uploaded_image} =
        Cloudex.upload(["./test/assets/test.jpg"], %{
          phash: "true",
          request_options: [recv_timeout: 60000, max_redirect: 3]
        })

      assert uploaded_image.phash != nil
    end
  end

  test "upload with context" do
    use_cassette "test_upload_with_context" do
      {:ok, uploaded_image} =
        Cloudex.upload(["./test/assets/test.jpg"], %{
          context: %{foo: "bar"},
          request_options: [recv_timeout: 60000, max_redirect: 3]
        })

      assert uploaded_image.context != nil
    end
  end

  test "delete image with public id" do
    use_cassette "test_delete" do
      assert {:ok, %Cloudex.DeletedImage{public_id: "rurwrndtvgzfajljllnr"}} =
               Cloudex.delete("rurwrndtvgzfajljllnr", %{
                 request_options: [recv_timeout: 60000, max_redirect: 3]
               })
    end
  end

  test "delete image with invalid public id" do
    use_cassette "test_delete_invalid" do
      assert {:ok, %Cloudex.DeletedImage{public_id: "thisIsABogusId"}} =
               Cloudex.delete("thisIsABogusId", %{
                 request_options: [recv_timeout: 60000, max_redirect: 3]
               })
    end
  end

  test "delete images from a list of public id's" do
    use_cassette "test_delete_list" do
      assert [
               {:ok, %Cloudex.DeletedImage{public_id: "vv7cxdopasmev61rhnzo"}},
               {:ok, %Cloudex.DeletedImage{public_id: "mdqzqlszjmfg9ih5tjsw"}}
             ] = Cloudex.delete(["vv7cxdopasmev61rhnzo", "mdqzqlszjmfg9ih5tjsw"])
    end
  end

  test "delete images for a prefix" do
    use_cassette "test_delete_prefix" do
      assert {:ok, "some_prefix"} = Cloudex.delete_prefix("some_prefix")
    end
  end

  test "delete private image" do
    use_cassette "test_private_image" do
      assert {:ok, %Cloudex.DeletedImage{public_id: "eMUnBDShgtAfxcdx"}} =
               Cloudex.delete("eMUnBDShgtAfxcdx", %{
                 resource_type: "image",
                 type: "private",
                 request_options: [recv_timeout: 60000, max_redirect: 3]
               })
    end
  end

  test "create a uploaded image from a map" do
    {:ok, data} = @json_library.decode(File.read!("./test/cloudinary_response.json"))
    result = Cloudex.CloudinaryApi.json_result_to_struct(data, "http://example.org/test.jpg")

    assert %Cloudex.UploadedImage{
             bytes: 22659,
             created_at: "2015-11-27T10:02:23Z",
             etag: "dbb5764565c1b77ff049d20fcfd1d41d",
             format: "jpg",
             height: 167,
             original_filename: "test",
             public_id: "i2nruesgu4om3w9mtk1z",
             resource_type: "image",
             secure_url:
               "https://d1vibqt9pdnk2f.cloudfront.net/image/upload/v1448618543/i2nruesgu4om3w9mtk1z.jpg",
             signature: "77b447746476c82bb4921fdea62a9227c584974b",
             source: "http://example.org/test.jpg",
             tags: [],
             type: "upload",
             url:
               "http://images.cloudassets.mobi/image/upload/v1448618543/i2nruesgu4om3w9mtk1z.jpg",
             version: 1_448_618_543,
             width: 250
           } = result
  end

  test "uploads a file in chunks" do
    use_cassette "test_upload_large", match_requests_on: [:headers] do
      result =
        Cloudex.upload_large(["./test/assets/test_chunk.mp4"], 6_000_000, %{
          resource_type: "video",
          request_options: [recv_timeout: 60000, max_redirect: 3]
        })

      assert {
               :ok,
               %Cloudex.UploadedVideo{
                 audio: %{
                   "bit_rate" => "192050",
                   "channel_layout" => "stereo",
                   "channels" => 2,
                   "codec" => "aac",
                   "frequency" => 48000
                 },
                 bit_rate: 3_717_305,
                 bytes: 10_544_601,
                 created_at: "2020-05-26T05:24:29Z",
                 duration: 22.692667,
                 eager: [],
                 etag: "b4b0bd86de486821d2d7470df805dc84",
                 format: "mp4",
                 frame_rate: 23.976023976023978,
                 height: 1080,
                 original_filename: "blob",
                 public_id: "v0awggmxai7blns99rcq",
                 resource_type: "video",
                 secure_url:
                   "https://res.cloudinary.com/my_cloud_name/video/upload/v1590470669/v0awggmxai7blns99rcq.mp4",
                 signature: "0e2ea0962818e79049d172e7bb7e1ede4fc5b114",
                 source: "./test/assets/test_chunk.mp4",
                 tags: '',
                 type: "upload",
                 url:
                   "http://res.cloudinary.com/my_cloud_name/video/upload/v1590470669/v0awggmxai7blns99rcq.mp4",
                 version: 1_590_470_669,
                 video: %{
                   "bit_rate" => "3533379",
                   "codec" => "h264",
                   "level" => 42,
                   "pix_format" => "yuv420p",
                   "profile" => "High"
                 },
                 width: 1920,
                 context: nil,
                 moderation: nil,
                 phash: nil
               }
             } = result
    end
  end

  test "returns an error if one of the chunks returns an error" do
    use_cassette "test_upload_large_error", match_requests_on: [:headers] do
      result =
        Cloudex.upload_large(["./test/assets/test_chunk.mp4"], 6_000_000, %{
          resource_type: "video",
          request_options: [recv_timeout: 60000, max_redirect: 3]
        })

      assert {:error,
              %{
                "error" => %{
                  "message" => "Chunk size doesn't match upload size: 6000000 - 5786816"
                }
              }} = result
    end
  end
end
