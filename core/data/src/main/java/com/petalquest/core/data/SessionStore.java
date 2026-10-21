package com.petalquest.core.data;

import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.AtomicFile;
import org.json.JSONObject;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** AES-GCM credentials in no_backup. All operations must be called on a background thread. */
public final class SessionStore {
    private static final String KEY_ALIAS = "petalquest.session.aes.v1";
    private static final byte[] AAD = "petalquest.session.v1".getBytes(StandardCharsets.UTF_8);
    private final AtomicFile file;
    private final FamilyDatabase family;

    SessionStore(File directory, FamilyDatabase family) {
        this.file = new AtomicFile(new File(directory, "session.enc"));
        this.family = family;
    }

    public Session read() {
        synchronized (LocalData.LOCK) {
            if (!file.getBaseFile().exists() && !new File(file.getBaseFile().getPath() + ".bak").exists()) return null;
            try {
                byte[] bytes = file.readFully();
                if (bytes.length < 29 || bytes[0] != 1) throw new IllegalStateException("Unsupported session format");
                byte[] iv = java.util.Arrays.copyOfRange(bytes, 1, 13);
                Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
                cipher.init(Cipher.DECRYPT_MODE, key(false), new GCMParameterSpec(128, iv));
                cipher.updateAAD(AAD);
                JSONObject json = new JSONObject(new String(cipher.doFinal(bytes, 13, bytes.length-13), StandardCharsets.UTF_8));
                return new Session(json.getString("userId"), json.getString("endpointId"), json.getString("token"),
                    json.getString("refreshToken"), json.getLong("expiresAtEpochSeconds"), json.getString("generation"));
            } catch (Exception e) {
                // Do not overwrite damaged credentials or silently bind a previous cache to another user.
                throw new IllegalStateException("Stored session could not be decrypted; explicit local reset is required", e);
            }
        }
    }

    public void save(Session session) {
        if (session == null) throw new IllegalArgumentException("Session is required");
        synchronized (LocalData.LOCK) {
            Session previous = read();
            // Switching identity first durably clears its family state. A crash can require refetching,
            // but cannot publish previous-user data under new credentials.
            if (previous != null && (!previous.userId.equals(session.userId) || !previous.endpointId.equals(session.endpointId))) {
                clearFamily(previous);
            }
            FileOutputStream output = null;
            try {
                JSONObject json = new JSONObject();
                json.put("userId", session.userId).put("endpointId", session.endpointId).put("token", session.token)
                    .put("refreshToken", session.refreshToken).put("expiresAtEpochSeconds", session.expiresAtEpochSeconds)
                    .put("generation", previous != null && previous.userId.equals(session.userId) && previous.endpointId.equals(session.endpointId)
                        ? previous.generation : session.generation);
                Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
                cipher.init(Cipher.ENCRYPT_MODE, key(true));
                cipher.updateAAD(AAD);
                byte[] encrypted = cipher.doFinal(json.toString().getBytes(StandardCharsets.UTF_8));
                byte[] framed = ByteBuffer.allocate(1+cipher.getIV().length+encrypted.length)
                    .put((byte)1).put(cipher.getIV()).put(encrypted).array();
                output = file.startWrite();
                output.write(framed);
                file.finishWrite(output);
            } catch (Exception e) {
                if (output != null) file.failWrite(output);
                throw new IllegalStateException("Session could not be persisted", e);
            }
        }
    }

    /** Clears current family cache and queue, then auth. Private health is retained. */
    public void clear() {
        synchronized (LocalData.LOCK) {
            Session previous = read();
            if (previous != null) clearFamily(previous);
            eraseCredentials();
        }
    }

    void eraseCredentials() {
        file.delete();
        if (file.getBaseFile().exists()) throw new IllegalStateException("Session deletion failed");
    }

    private void clearFamily(Session session) {
        family.runInTransaction(() -> {
            family.familyDao().clearCache(session.userId, session.endpointId);
            family.familyDao().clearQueue(session.userId, session.endpointId);
        });
    }

    private static SecretKey key(boolean create) throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if (store.containsAlias(KEY_ALIAS)) return (SecretKey)store.getKey(KEY_ALIAS, null);
        if (!create) throw new IllegalStateException("Session encryption key unavailable");
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
        return generator.generateKey();
    }
}
