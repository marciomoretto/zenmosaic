# frozen_string_literal: true

module Zenmosaic
  module CoordinateTransformer
    WGS84_A = 6_378_137.0
    WGS84_F = 1.0 / 298.257223563
    WGS84_E2 = WGS84_F * (2 - WGS84_F)
    WGS84_E_PRIME2 = WGS84_E2 / (1.0 - WGS84_E2)
    K0 = 0.9996

    module_function

    def build(target_crs)
      epsg = parse_epsg(target_crs)

      case epsg
      when 4326
        lambda do |longitude, latitude|
          [Float(longitude), Float(latitude)]
        end
      when 32_601..32_660
        zone = epsg - 32_600
        lambda do |longitude, latitude|
          wgs84_to_utm(longitude, latitude, zone: zone, hemisphere: :north)
        end
      when 32_701..32_760
        zone = epsg - 32_700
        lambda do |longitude, latitude|
          wgs84_to_utm(longitude, latitude, zone: zone, hemisphere: :south)
        end
      else
        raise Error, "CRS '#{target_crs}' nao suportado. Use EPSG:4326, EPSG:326xx ou EPSG:327xx"
      end
    end

    def parse_epsg(target_crs)
      text = target_crs.to_s.strip.upcase
      match = text.match(/\AEPSG:(\d{4,5})\z/)
      raise Error, "target_crs invalido: '#{target_crs}'" if match.nil?

      match[1].to_i
    end

    def wgs84_to_utm(longitude, latitude, zone:, hemisphere:)
      lon = Float(longitude)
      lat = Float(latitude)

      lat_rad = to_radians(lat)
      lon_rad = to_radians(lon)

      lon0_deg = (zone - 1) * 6 - 180 + 3
      lon0_rad = to_radians(lon0_deg)

      sin_lat = Math.sin(lat_rad)
      cos_lat = Math.cos(lat_rad)
      tan_lat = Math.tan(lat_rad)

      n = WGS84_A / Math.sqrt(1.0 - WGS84_E2 * sin_lat**2)
      t = tan_lat**2
      c = WGS84_E_PRIME2 * cos_lat**2
      a = cos_lat * (lon_rad - lon0_rad)

      m = meridional_arc(lat_rad)

      easting = K0 * n * (
        a +
        (1 - t + c) * a**3 / 6.0 +
        (5 - 18 * t + t**2 + 72 * c - 58 * WGS84_E_PRIME2) * a**5 / 120.0
      ) + 500_000.0

      northing = K0 * (
        m +
        n * tan_lat * (
          a**2 / 2.0 +
          (5 - t + 9 * c + 4 * c**2) * a**4 / 24.0 +
          (61 - 58 * t + t**2 + 600 * c - 330 * WGS84_E_PRIME2) * a**6 / 720.0
        )
      )

      northing += 10_000_000.0 if hemisphere == :south

      [easting, northing]
    end

    def meridional_arc(lat_rad)
      e2 = WGS84_E2
      e4 = e2**2
      e6 = e2**3

      WGS84_A * (
        (1 - e2 / 4.0 - 3 * e4 / 64.0 - 5 * e6 / 256.0) * lat_rad -
        (3 * e2 / 8.0 + 3 * e4 / 32.0 + 45 * e6 / 1024.0) * Math.sin(2 * lat_rad) +
        (15 * e4 / 256.0 + 45 * e6 / 1024.0) * Math.sin(4 * lat_rad) -
        (35 * e6 / 3072.0) * Math.sin(6 * lat_rad)
      )
    end

    def to_radians(value)
      Float(value) * Math::PI / 180.0
    end
  end
end
