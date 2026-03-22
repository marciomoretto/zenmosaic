# Zenmosaic

Gem Ruby/Rails para pipeline de mosaico de imagens de drone a partir de uma lista de arquivos.

Fluxo principal:

1. Recebe um array de paths de imagens.
2. Extrai metadados EXIF + XMP DJI.
3. Calcula footprints no solo no CRS do profile.
4. Gera preview e manifest JSON (opcional).
5. Renderiza mosaico final (PNG nativo + JPG comprimido).

## Requisitos

- Ruby >= 3.0
- Gem exifr (~> 1.4)
- ImageMagick instalado para render:
  - convert
  - identify
  - composite

## Instalacao

```ruby
gem "zenmosaic", path: "../zenmosaic"
```

```bash
bundle install
```

## Configuracao no Rails

```ruby
# config/initializers/zenmosaic.rb
Rails.application.configure do
  config.zenmosaic.enabled = true
  config.zenmosaic.label_prefix = "Zen"

  # Base para paths relativos (opcional)
  config.zenmosaic.images_root = Rails.root.join("storage", "drone_images").to_s
end
```

## Profile do cliente

Os dados tecnicos devem ser passados pelo cliente da gem via `profile_data`.

```ruby
profile_data = {
  expected_camera_models: nil,
  fov_diag_deg: 84.0,
  aspect_ratio: [4, 3],
  agl_offset_m: 0.0,
  expected_relative_altitude_m: 70.0,
  alt_tolerance_m: 5.0,
  target_crs: "EPSG:32723"
}
```

Se `profile_data` nao for informado, a gem usa profiles internos por nome (`profile:`).

## API

### Metadados por lista de arquivos

```ruby
result = Zenmosaic.extract_files_metadata(
  profile: "air3s_wide_70m_rj",
  profile_data: profile_data,
  paths: [
    "/dados/missao/img_0001.jpg",
    "/dados/missao/img_0002.jpg"
  ]
)
```

Retorno:

- `result[:request]`
- `result[:images]`

### Footprints por lista de arquivos

```ruby
result = Zenmosaic.build_footprints(
  profile: "air3s_wide_70m_rj",
  profile_data: profile_data,
  paths: [
    "/dados/missao/img_0001.jpg",
    "/dados/missao/img_0002.jpg"
  ],
  export_geojson: true,
  output_dir: "/tmp/zen_out"
)
```

Retorno:

- `result[:request]`
- `result[:collection]`
- `result[:target_crs]`, `result[:fov_diag_deg]`, etc.

### Preview por lista de arquivos

```ruby
result = Zenmosaic.build_preview(
  profile: "air3s_wide_70m_rj",
  profile_data: profile_data,
  paths: [
    "/dados/missao/img_0001.jpg",
    "/dados/missao/img_0002.jpg"
  ],
  export_geojson: true,
  export_manifest: true,
  output_dir: "/tmp/zen_out"
)
```

Retorno:

- `result[:request]`
- `result[:footprints]`
- `result[:preview]`
- `result[:collection]`

### Render de mosaico por lista de arquivos

```ruby
result = Zenmosaic.render_mosaic(
  profile: "air3s_wide_70m_rj",
  profile_data: profile_data,
  paths: [
    "/dados/missao/img_0001.jpg",
    "/dados/missao/img_0002.jpg"
  ],
  export_geojson: true,
  export_manifest: true,
  output_dir: "/tmp/zen_out",
  max_images_to_plot: 12,
  downsample_native: 1,
  compressed_scale: 0.35,
  compressed_quality: 88
)
```

Retorno:

- `result[:request]`
- `result[:mosaics]`
- `result[:collection][:output_path_native]`
- `result[:collection][:output_path_compressed]`

## Testes

```bash
bundle exec rake test
```
