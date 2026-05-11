INSTALL spatial;
INSTALL httpfs;

LOAD spatial;
LOAD httpfs;

CREATE OR REPLACE TABLE osm_data AS
SELECT *
FROM ST_Read('map.geojson');

CREATE OR REPLACE TABLE links AS
WITH raw_data AS (
	SELECT *
	FROM 'https://stac.overturemaps.org/2026-04-15.0/buildings/building/collection.json'
),
raw_links AS (
	SELECT unnest(links) AS link
	FROM raw_data
),
links AS (
	SELECT row_number() OVER () id, link.href
	FROM raw_links
	WHERE link.type = 'application/geo+json'
),
raw_bboxes AS (
	SELECT unnest(extent.spatial.bbox) bbox
	FROM raw_data
),
bboxes AS (
	SELECT row_number() OVER () id, bbox[1] xmin, bbox[2] ymin, bbox[3] xmax, bbox[4] ymax
	FROM raw_bboxes
)
SELECT href, xmin, ymin, xmax, ymax
FROM links
JOIN bboxes ON links.id = bboxes.id;

SELECT DISTINCT 'https://stac.overturemaps.org/2026-04-15.0/buildings/building/' || links.href link
FROM links
JOIN osm_data ON ST_Xmin(geom) BETWEEN links.xmin AND links.xmax
AND ST_Ymin(geom) BETWEEN links.ymin AND links.ymax;

SELECT assets.aws.alternate.s3.href
FROM 'https://stac.overturemaps.org/2026-04-15.0/buildings/building/./00444/00444.json';

CREATE OR REPLACE TABLE overture_data AS
WITH osm_data_geom_bbox AS (
	SELECT ST_Extent_Agg(geom) geom
	FROM osm_data
),
osm_data_bbox AS (
	SELECT ST_Xmin(geom) AS xmin,
		ST_Ymin(geom) AS ymin,
		ST_Xmax(geom) AS xmax,
		ST_Ymax(geom) AS ymax
	FROM osm_data_geom_bbox
)
SELECT *
FROM read_parquet('s3://overturemaps-us-west-2/release/2026-04-15.0/theme=buildings/type=building/part-00444-4ebd20bb-df8b-51bf-bf04-9eca0f9b119c-c000.zstd.parquet') data
JOIN osm_data_bbox ON ST_Xmin(geometry) BETWEEN osm_data_bbox.xmin AND osm_data_bbox.xmax
AND ST_Ymin(geometry) BETWEEN osm_data_bbox.ymin AND osm_data_bbox.ymax;


SELECT unnest(sources)
FROM overture_data overture
LEFT JOIN osm_data osm ON ST_Intersects(osm.geom, ST_Setcrs(overture.geometry, 'EPSG:4326'))
WHERE osm.building IS NOT NULL;


CREATE OR REPLACE TABLE overture_buildings AS
SELECT
    overture.*,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM osm_data osm
            WHERE osm.building IS NOT NULL
            AND ST_Intersects(osm.geom, ST_SetCRS(overture.geometry, 'EPSG:4326'))
        )
        THEN 'my'

        WHEN EXISTS (
            SELECT 1
            FROM (
                SELECT unnest(overture.sources) AS src
            )
            WHERE src.dataset = 'OpenStreetMap'
        )
        THEN 'osm'

        WHEN EXISTS (
            SELECT 1
            FROM (
                SELECT unnest(overture.sources) AS src
            )
            WHERE
                lower(src.dataset) LIKE '%ml%'
                OR lower(src.dataset) LIKE '%microsoft%'
                OR lower(src.dataset) LIKE '%google%'
        )
        THEN 'ml'

        ELSE 'ml'
    END AS source_type
FROM overture_data overture;



COPY (
    SELECT
        geometry,
        source_type,
        id
    FROM overture_buildings
)
TO './client/vite-project/public/overture.geojson'
WITH (FORMAT GDAL, DRIVER 'GeoJSON');