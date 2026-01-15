import { useState, useRef } from 'react';
import apiClient from '../api/client';

function ImageUploader({ label, currentImageUrl, onImageUploaded, disabled }) {
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState('');
  const fileInputRef = useRef(null);

  const handleFileSelect = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    // Vérifier le type de fichier
    if (!file.type.startsWith('image/')) {
      setError('Veuillez sélectionner une image');
      return;
    }

    // Vérifier la taille (max 5MB)
    if (file.size > 5 * 1024 * 1024) {
      setError('L\'image ne doit pas dépasser 5MB');
      return;
    }

    setError('');
    setUploading(true);

    try {
      const response = await apiClient.uploadImage(file);
      onImageUploaded(response.url);
    } catch (err) {
      setError(err.message || 'Erreur lors de l\'upload');
    } finally {
      setUploading(false);
    }
  };

  return (
    <div className="form-group">
      <label className="form-label">{label}</label>

      {currentImageUrl && (
        <div style={{ marginBottom: '12px' }}>
          <img
            src={currentImageUrl}
            alt="Preview"
            style={{
              maxWidth: '100%',
              maxHeight: '200px',
              borderRadius: '8px',
              objectFit: 'cover',
            }}
          />
        </div>
      )}

      <div style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
        <input
          ref={fileInputRef}
          type="file"
          accept="image/*"
          onChange={handleFileSelect}
          disabled={disabled || uploading}
          style={{ display: 'none' }}
        />

        <button
          type="button"
          className="btn btn-secondary"
          onClick={() => fileInputRef.current?.click()}
          disabled={disabled || uploading}
        >
          {uploading ? '⏳ Upload...' : '📤 Choisir une image'}
        </button>

        {currentImageUrl && (
          <button
            type="button"
            className="btn btn-secondary"
            onClick={() => onImageUploaded('')}
            disabled={disabled || uploading}
          >
            🗑️ Supprimer
          </button>
        )}
      </div>

      {error && (
        <p style={{ color: 'var(--danger)', fontSize: '14px', marginTop: '8px', marginBottom: 0 }}>
          {error}
        </p>
      )}

      <p style={{ fontSize: '14px', color: 'var(--text-muted)', marginTop: '8px', marginBottom: 0 }}>
        Formats acceptés: JPG, PNG, GIF. Taille max: 5MB
      </p>
    </div>
  );
}

export default ImageUploader;
