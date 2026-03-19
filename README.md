# Zenmosaic

Gem Ruby/Rails para pipeline de mosaico de fotos de drone, com foco em uso por servicos/jobs.

Pipeline principal:

1. Resolve profile e pasta de trabalho.
2. Extrai metadados EXIF + XMP DJI das imagens.
3. Calcula footprints no chao (com projecao para o CRS do profile).
4. Gera dados de preview (manifest opcional em JSON).
5. Renderiza mosaico final (PNG + JPG).

Tambem existe modo de compatibilidade por lista de subpastas (horarios), alem do modo recomendado de pasta unica.

## Requisitos

- Ruby >= 3.0
- Gem exifr (~> 1.4)
- ImageMagick instalado no sistema para render:
	- convert
	- identify
	- composite

Observacao: metadados, footprints e preview funcionam sem ImageMagick. So o render precisa desses binarios.

## Instalacao

No Gemfile da app Rails:

```ruby
gem "zenmosaic", path: "../zenmosaic"
# ou: gem "zenmosaic" (se publicada)
```

Depois:

```bash
bundle install
```

## Configuracao no Rails

Crie ou ajuste o initializer:

```ruby
# config/initializers/zenmosaic.rb
Rails.application.configure do
	config.zenmosaic.enabled = true
	config.zenmosaic.label_prefix = "Zen"

	# Base para pastas relativas (folder)
	config.zenmosaic.images_root = Rails.root.join("storage", "drone_batches").to_s

	# Profile usado quando profile: nao e informado
	config.zenmosaic.default_profile = "air3s_wide_70m_rj"

	# Pode sobrescrever/estender perfis
	config.zenmosaic.profiles["air3s_wide_70m_rj"] = {
		expected_camera_models: nil,
		fov_diag_deg: 84.0,
		aspect_ratio: [4, 3],
		agl_offset_m: 0.0,
		expected_relative_altitude_m: 70.0,
		alt_tolerance_m: 5.0,
		target_crs: "EPSG:32723"
	}
end
```

Perfis padrao atuais:

- air3s_wide_70m_rj
- mavic3pro_wide_sp
- mavic3pro_mediumtele_sp

## Como folder e resolvido

API base:

```ruby
request = Zenmosaic.build_processing_request(profile: nil, folder:)
```

Regras:

- Se profile: for nil, usa default_profile.
- Se folder for caminho absoluto, usa esse caminho direto.
- Se folder for relativo e images_root estiver configurado, usa images_root/folder.
- Se folder for relativo e images_root nao estiver configurado, usa folder como informado.

Retorno (objeto Zenmosaic::ProcessingRequest):

- request.profile_name
- request.folder_name
- request.folder_path
- request.profile

## Metadados

### Arquivo unico

```ruby
data = Zenmosaic.extract_image_metadata("/caminho/foto.jpg")
```

### Pasta inteira (recursivo)

```ruby
result = Zenmosaic.extract_batch_metadata(profile: nil, folder: "lote_001")
```

Retorno:

- result[:request] -> contexto resolvido
- result[:images] -> array de metadados por arquivo

Extensoes consideradas:

- .jpg
- .jpeg
- .tif
- .tiff
- .png

Campos tipicos por imagem (quando disponiveis):

- file_name
- file_path
- image_width, image_height
- camera_make, camera_model, lens_model
- focal_length, focal_length_35mm
- iso, f_number, exposure_time_seconds
- gps_latitude, gps_longitude, gps_altitude
- dji_relative_altitude
- dji_flight_yaw_degree
- dji_gimbal_pitch_degree
- dji_gimbal_yaw_degree

### Inventario por subpastas (compatibilidade)

```ruby
result = Zenmosaic.extract_hourly_metadata(
	profile: nil,
	folder: "lote_001",
	subfolders: ["14.00", "14.10"]
)
```

Retorno:

- result[:request]
- result[:folders] -> lista com:
	- :folder
	- :folder_path
	- :images_count
	- :rows

### Inventario de pasta unica (recomendado)

```ruby
result = Zenmosaic.extract_folder_metadata(profile: nil, folder: "18.00")
```

Retorno:

- result[:request]
- result[:folder] -> mesma estrutura de uma entrada de result[:folders]

## Footprints

### Pasta unica (recomendado)

```ruby
result = Zenmosaic.build_folder_footprints(
	profile: nil,
	folder: "18.00",
	export_geojson: false,
	output_dir: nil,
	pitch_tolerance_deg: 2.0,
	default_height_agl_m: 70.0
)
```

### Multi-subpastas

```ruby
result = Zenmosaic.build_hourly_footprints(
	profile: nil,
	folder: "lote_001",
	subfolders: ["14.00", "14.10"],
	export_geojson: false,
	output_dir: nil,
	pitch_tolerance_deg: 2.0,
	default_height_agl_m: 70.0
)
```

O processamento inclui:

- Selecao e normalizacao de colunas
- Filtro de GPS valido
- Filtro de fotos zenitais (pitch perto de -90)
- Calculo de yaw/rotacao
- Altura AGL (com fallback quando nao houver altitude relativa DJI)
- Projecao para o target_crs do profile
- Geometria Polygon por imagem

Retorno por pasta:

- input_count, images_count
- used_columns
- dropped_counts
- altitude_check
- expected_footprint_70m_m
- sample_centers_xy
- bounds
- rows (com geometry, x0, y0, half_w, half_h, rotation_deg, etc)
- geojson_path (quando export_geojson: true)
- warnings, error

Quando export_geojson: true, o arquivo salvo e:

- drone_footprints_<profile>_<folder>.geojson

## Preview

### Pasta unica (recomendado)

```ruby
result = Zenmosaic.build_folder_preview(
	profile: nil,
	folder: "18.00",
	images_dir: nil,
	max_images_to_plot: 12,
	downsample: 6,
	export_geojson: false,
	output_dir: nil,
	export_manifest: true,
	pitch_tolerance_deg: 2.0,
	default_height_agl_m: 70.0
)
```

### Multi-subpastas

```ruby
result = Zenmosaic.build_hourly_preview(
	profile: nil,
	folder: "lote_001",
	subfolders: ["14.00", "14.10"],
	images_base_dir: nil,
	max_images_to_plot: 12,
	downsample: 6,
	export_geojson: false,
	output_dir: nil,
	export_manifest: true,
	pitch_tolerance_deg: 2.0,
	default_height_agl_m: 70.0
)
```

Detalhes importantes de caminho:

- build_hourly_preview usa images_base_dir (default: request.folder_path)
- build_folder_preview usa images_dir (default: diretorio pai de request.folder_path)
- Para cada pasta, o preview procura imagens em images_base_dir/<folder>

Retorno de preview por pasta:

- folder
- images_dir
- attempted, plotted, failed, skipped
- bounds
- items
	- filename
	- filename_only
	- image_path
	- downsample
	- transform (x0, y0, half_w, half_h, rotation_deg)
	- geometry
- warnings
- manifest_path (quando export_manifest: true)

Manifest JSON (opcional):

- drone_preview_<profile>_<folder>.json

## Render do mosaico

### Pasta unica (recomendado)

```ruby
result = Zenmosaic.render_folder_mosaic(
	profile: nil,
	folder: "18.00",
	images_dir: nil,
	max_images_to_plot: 12,
	downsample: 6,
	downsample_native: 1,
	compressed_scale: 0.35,
	compressed_quality: 88,
	export_geojson: true,
	output_dir: nil,
	export_manifest: true,
	pitch_tolerance_deg: 2.0,
	default_height_agl_m: 70.0
)
```

### Multi-subpastas

```ruby
result = Zenmosaic.render_hourly_mosaics(
	profile: nil,
	folder: "lote_001",
	subfolders: ["14.00", "14.10"],
	images_base_dir: nil,
	max_images_to_plot: 12,
	downsample: 6,
	downsample_native: 1,
	compressed_scale: 0.35,
	compressed_quality: 88,
	export_geojson: true,
	output_dir: nil,
	export_manifest: true,
	pitch_tolerance_deg: 2.0,
	default_height_agl_m: 70.0
)
```

Arquivos finais por pasta:

- mosaico_resolucao_nativa_<profile>_<folder>.png
- mosaico_comprimido_<profile>_<folder>.jpg

Retorno por pasta (render):

- folder
- attempted, plotted, failed
- principal_angle_deg, global_rotation_deg
- pixels_per_unit
- canvas_width_px, canvas_height_px
- output_path_native
- output_path_compressed
- warnings

## Fluxo recomendado no Rails

Para o caso atual (uma pasta = um horario), use direto:

```ruby
result = Zenmosaic.render_folder_mosaic(
	profile: params[:profile],
	folder: params[:folder],
	output_dir: Rails.root.join("tmp", "zenmosaic_mosaics").to_s,
	export_geojson: true,
	export_manifest: true
)

# Persistencia e responsabilidade da app:
# - result[:request]
# - result[:footprints]
# - result[:preview]
# - result[:mosaics]
# - result[:folder]
```

## Comportamento de erros e avisos

- Erros de validacao (ex: profile inexistente, pasta invalida, CRS nao suportado) geram Zenmosaic::Error.
- Durante processamento por pasta, varios casos viram warnings no retorno (sem interromper tudo), como:
	- nenhuma imagem encontrada
	- GPS invalido
	- sem yaw
	- sem altitude relativa DJI (usa fallback)
	- imagem nao encontrada na etapa de preview/render

## Helper de view

Disponivel automaticamente em ActionView via Railtie:

```erb
<%= zenmosaic_badge("online") %>
```

Se Zenmosaic.configuration.enabled for false, retorna string vazia.

## Desenvolvimento

```bash
bundle install
bundle exec rake test
```

## Licenca

MIT
