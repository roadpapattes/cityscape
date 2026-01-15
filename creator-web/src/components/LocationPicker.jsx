import { useState, useEffect, useRef } from 'react';
import { MapContainer, TileLayer, Marker, useMapEvents } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import L from 'leaflet';

// Fix for default marker icons in React-Leaflet
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
});

function LocationMarker({ position, setPosition }) {
  useMapEvents({
    click(e) {
      setPosition(e.latlng);
    },
  });

  return position === null ? null : <Marker position={position} />;
}

function LocationPicker({ label, latitude, longitude, onLocationChange, disabled }) {
  const [showMap, setShowMap] = useState(false);
  const [position, setPosition] = useState(
    latitude && longitude ? { lat: latitude, lng: longitude } : null
  );
  const mapRef = useRef(null);

  // Default center (Paris, France) if no position
  const defaultCenter = { lat: 48.8566, lng: 2.3522 };
  const center = position || defaultCenter;

  useEffect(() => {
    if (position) {
      onLocationChange(position.lat, position.lng);
    }
  }, [position]);

  const handleClearLocation = () => {
    setPosition(null);
    onLocationChange(null, null);
  };

  return (
    <div className="form-group">
      <label className="form-label">{label}</label>

      {/* Boutons d'action */}
      <div style={{ display: 'flex', gap: '12px', marginBottom: '12px' }}>
        <button
          type="button"
          className="btn btn-secondary"
          onClick={() => setShowMap(!showMap)}
          disabled={disabled}
        >
          {showMap ? '📍 Masquer la carte' : '🗺️ Sélectionner sur la carte'}
        </button>

        {position && (
          <button
            type="button"
            className="btn btn-secondary"
            onClick={handleClearLocation}
            disabled={disabled}
          >
            🗑️ Effacer
          </button>
        )}
      </div>

      {/* Carte interactive */}
      {showMap && (
        <div style={{ marginBottom: '16px' }}>
          <MapContainer
            center={[center.lat, center.lng]}
            zoom={13}
            style={{ height: '400px', width: '100%', borderRadius: '8px' }}
            ref={mapRef}
          >
            <TileLayer
              attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
              url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            />
            <LocationMarker position={position} setPosition={setPosition} />
          </MapContainer>
          <p style={{ fontSize: '14px', color: 'var(--text-muted)', marginTop: '8px', marginBottom: 0 }}>
            Cliquez sur la carte pour placer le marqueur
          </p>
        </div>
      )}

      {position && (
        <p style={{ fontSize: '14px', color: 'var(--success)', marginTop: '8px', marginBottom: 0 }}>
          ✓ Position sélectionnée: {position.lat.toFixed(6)}, {position.lng.toFixed(6)}
        </p>
      )}
    </div>
  );
}

export default LocationPicker;
