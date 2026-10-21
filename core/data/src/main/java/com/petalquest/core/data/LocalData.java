package com.petalquest.core.data;

import android.content.Context;
import androidx.room.Room;
import java.io.File;

/** Application-scoped owner. Keep one instance, and invoke storage operations on an IO executor. */
public final class LocalData implements AutoCloseable {
    static final Object LOCK = new Object();
    private static LocalData applicationInstance;

    /** One owner per application process; activity recreation must not leak Room handles. */
    public static LocalData getInstance(Context context) {
        synchronized (LOCK) {
            if (applicationInstance == null) applicationInstance = new LocalData(context.getApplicationContext());
            return applicationInstance;
        }
    }
    private final FamilyDatabase family;
    private final PrivateHealthDatabase health;
    private final SessionStore sessions;

    public LocalData(Context context) {
        Context app = context.getApplicationContext();
        File directory = new File(app.getNoBackupFilesDir(), "petalquest");
        if (!directory.isDirectory() && !directory.mkdirs()) throw new IllegalStateException("Private data directory unavailable");
        family = Room.databaseBuilder(app, FamilyDatabase.class, new File(directory, "family_cache.db").getAbsolutePath()).build();
        health = Room.databaseBuilder(app, PrivateHealthDatabase.class, new File(directory, "private_health.db").getAbsolutePath()).build();
        sessions = new SessionStore(directory, family);
    }

    public SessionStore sessionStore() { return sessions; }
    public void activate(Session session) { sessions.save(session); }
    public void logout() { sessions.clear(); }

    /** Creates an identity-bound handle; every operation verifies it still matches active credentials. */
    public FamilyRepository family(String userId, String endpointId) {
        return new FamilyRepository(family, sessions, Session.required(userId, "userId"), Session.normalizeEndpoint(endpointId));
    }

    /** Explicit recovery action only: discards ALL family caches/queues and credentials, retaining health. */
    public void resetLocalFamilyAndSession() {
        synchronized (LOCK) {
            family.clearAllTables();
            sessions.eraseCredentials();
        }
    }

    @Override public void close() {
        synchronized (LOCK) { family.close(); health.close(); }
    }
}
