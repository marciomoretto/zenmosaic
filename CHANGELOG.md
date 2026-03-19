# Changelog

## [0.1.0] - 2026-03-18

- Versao inicial da gem com suporte a Rails via Railtie.
- Configuracao global da gem.
- Helper de view para exibir badge.
- Catalogo de perfis de drone padrao para execucao.
- API `Zenmosaic.build_processing_request(profile:, folder:)` para substituir input interativo do Colab.
- Extrator de metadados EXIF + XMP DJI para arquivo e pasta.
- API `Zenmosaic.extract_batch_metadata(profile:, folder:)` para processar lote completo.
- API `Zenmosaic.extract_hourly_metadata(...)` para varrer subpastas por horario.
- Processamento por subpasta em memoria para persistencia no app Rails.
- Transformacao de coordenadas WGS84 para EPSG:326xx/EPSG:327xx e EPSG:4326.
- Pipeline `Zenmosaic.build_hourly_footprints(...)` para filtrar zenitais, calcular AGL e gerar footprints.
- Exportacao opcional de GeoJSON por horario.
- API `Zenmosaic.build_hourly_preview(...)` para gerar manifest JSON de visualizacao por horario.
- Resolucao robusta de caminho de imagem com fallback de extensoes/caixa alta/baixa.
- API `Zenmosaic.render_hourly_mosaics(...)` para gerar mosaico desentortado por horario.
- Saida em versao nativa PNG e versao comprimida JPG.
- APIs de pasta unica: `extract_folder_metadata`, `build_folder_footprints`, `build_folder_preview`, `render_folder_mosaic`.
- Fluxo recomendado no Rails simplificado para um unico horario por pasta.
