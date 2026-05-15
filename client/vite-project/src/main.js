import 'ol/ol.css';
import Map from 'ol/Map';
import View from 'ol/View';
import TileLayer from 'ol/layer/Tile';
import OSM from 'ol/source/OSM';
import VectorSource from 'ol/source/Vector';
import VectorLayer from 'ol/layer/Vector';
import { applyStyle } from 'ol-mapbox-style';
import GeoJSON from 'ol/format/GeoJSON';
import ImageLayer from 'ol/layer/Image';
import ImageWMS from 'ol/source/ImageWMS';
import {fromLonLat} from "ol/proj.js";

const overtureSource = new VectorSource();

fetch('/overture.geojson')
  .then(response => {
    return response.json();
  })
  .then(data => {
    const features = new GeoJSON().readFeatures(data, {
      dataProjection: 'EPSG:4326',
      featureProjection: 'EPSG:3857'
    });

    overtureSource.clear();
    overtureSource.addFeatures(features);
  })

const overtureLayer = new VectorLayer({
  source: overtureSource
});

const overtureStyles = fetch('/overture-styles.json').then(response => response.json());

applyStyle(overtureLayer, overtureStyles, 'overture', {
  updateSource: false
});

new Map({
  target: 'map',
  layers: [
    new TileLayer({
      source: new OSM()
    }),
    new ImageLayer({
      source: new ImageWMS({
        url: 'http://localhost:8080/geoserver/gis/wms',
        params: {
          LAYERS: 'gis:buildings',
          TILED: true
        },
        ratio: 1,
        serverType: 'geoserver'
      })
    }),
    overtureLayer
  ],
  view: new View({
    center: fromLonLat([49.842540740966795, 53.47374153137207]),
    zoom: 19
  })
});