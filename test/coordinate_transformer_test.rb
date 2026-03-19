# frozen_string_literal: true

require "test_helper"

class CoordinateTransformerTest < Minitest::Test
  def test_epsg_4326_identity_projection
    projector = Zenmosaic::CoordinateTransformer.build("EPSG:4326")
    x, y = projector.call(-46.1234, -23.5678)

    assert_in_delta(-46.1234, x, 0.000001)
    assert_in_delta(-23.5678, y, 0.000001)
  end

  def test_epsg_32723_utm_projection
    projector = Zenmosaic::CoordinateTransformer.build("EPSG:32723")
    x, y = projector.call(-45.0, -23.0)

    assert_in_delta 500_000.0, x, 100.0
    assert y > 7_000_000
    assert y < 8_000_000
  end

  def test_unsupported_crs_raises_error
    error = assert_raises(Zenmosaic::Error) do
      Zenmosaic::CoordinateTransformer.build("EPSG:3857")
    end

    assert_match "nao suportado", error.message
  end
end
