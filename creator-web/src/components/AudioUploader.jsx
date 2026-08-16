import { useState, useRef } from 'react';
import apiClient from '../api/client';

const MIN_DURATION_SECONDS = 60;
const MAX_FILE_SIZE = 20 * 1024 * 1024;

function AudioUploader({ label, currentAudioUrl, onAudioUploaded, disabled }) {
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState('');
  const fileInputRef = useRef(null);

  const readDuration = (file) =>
    new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file);
      const audio = new Audio();
      audio.preload = 'metadata';
      audio.onloadedmetadata = () => {
        URL.revokeObjectURL(url);
        resolve(audio.duration);
      };
      audio.onerror = () => {
        URL.revokeObjectURL(url);
        reject(new Error('Impossible de lire ce fichier audio'));
      };
      audio.src = url;
    });

  const handleFileSelect = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (!file.type.startsWith('audio/')) {
      setError('Veuillez sélectionner un fichier audio');
      return;
    }

    if (file.size > MAX_FILE_SIZE) {
      setError('Le fichier ne doit pas dépasser 20MB');
      return;
    }

    setError('');
    setUploading(true);

    try {
      // Pré-check côté navigateur : évite un upload inutile si le fichier est
      // manifestement trop court. Le serveur reste la source de vérité.
      try {
        const duration = await readDuration(file);
        if (Number.isFinite(duration) && duration < MIN_DURATION_SECONDS) {
          setError(
            `Le fond sonore doit durer au moins ${MIN_DURATION_SECONDS} secondes ` +
            `(durée détectée : ${Math.round(duration)}s)`
          );
          setUploading(false);
          return;
        }
      } catch {
        // Pré-check impossible (format non lisible par le navigateur) : on
        // laisse le serveur trancher, il refusera si besoin.
      }

      const response = await apiClient.uploadAudio(file);
      onAudioUploaded(response.url);
    } catch (err) {
      setError(err.message || 'Erreur lors de l\'upload');
    } finally {
      setUploading(false);
    }
  };

  return (
    <div className="form-group">
      <label className="form-label">{label}</label>

      {currentAudioUrl && (
        <div style={{ marginBottom: '12px' }}>
          <audio controls src={currentAudioUrl} style={{ width: '100%' }} />
        </div>
      )}

      <div style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
        <input
          ref={fileInputRef}
          type="file"
          accept="audio/*"
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
          {uploading ? '⏳ Upload...' : '📤 Choisir un fond sonore'}
        </button>

        {currentAudioUrl && (
          <button
            type="button"
            className="btn btn-secondary"
            onClick={() => onAudioUploaded('')}
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
        Formats acceptés : MP3, M4A/AAC. Durée minimale : {MIN_DURATION_SECONDS}s (joué en boucle
        pendant la partie). Taille max : 20MB. À toi de vérifier les droits d'auteur du fichier.
      </p>
    </div>
  );
}

export default AudioUploader;
