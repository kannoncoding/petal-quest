package petalquest.verification;

import android.content.Context;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import com.petalquest.core.data.FamilyRepository;
import com.petalquest.core.data.LocalData;
import com.petalquest.core.data.PendingOperation;
import com.petalquest.core.data.Session;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.UUID;
import static org.junit.Assert.*;

/** Synthetic data only, in the verification target application's private sandbox. */
@RunWith(AndroidJUnit4.class)
public final class LocalDataVerificationTest {
    private static final String ENDPOINT = "https://verification.invalid";
    private static final String OTHER_ENDPOINT = "https://other-verification.invalid";
    private static final String ACCESS = "synthetic-access-token-never-valid";
    private static final String REFRESH = "synthetic-refresh-token-never-valid";
    private LocalData data;
    private File directory;
    private File sessionFile;

    @Before public void setUp() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        assertEquals("petalquest.verification", context.getPackageName());
        directory = new File(context.getNoBackupFilesDir(), "petalquest");
        sessionFile = new File(directory, "session.enc");
        data = new LocalData(context);
        data.resetLocalFamilyAndSession();
        data.activate(session("synthetic-user-a", ENDPOINT));
    }

    @After public void tearDown() {
        if (data != null) {
            try { data.resetLocalFamilyAndSession(); }
            finally { data.close(); }
        }
    }

    private Session session(String user, String endpoint) {
        return new Session(user, endpoint, ACCESS, REFRESH, 4102444800L);
    }

    private FamilyRepository family() { return data.family("synthetic-user-a", ENDPOINT); }

    private void reopen() {
        data.close();
        data = new LocalData(InstrumentationRegistry.getInstrumentation().getTargetContext());
    }

    private static void rejects(Class<? extends Throwable> expected, Runnable action) {
        try { action.run(); }
        catch (Throwable failure) {
            if (expected.isInstance(failure)) return;
            throw new AssertionError("Unexpected exception type", failure);
        }
        fail("Expected " + expected.getSimpleName());
    }

    private void addSnapshotAndIntent(FamilyRepository repository) {
        repository.cacheRemoteSnapshot(FamilyRepository.CacheKind.QUESTS, "synthetic-record", "{\"title\":\"fixture\"}");
        repository.enqueue(FamilyRepository.OperationKind.QUEST_SUBMIT, "{\"occurrence_id\":\"synthetic-occurrence\"}");
    }

    private File healthMarker() throws Exception {
        // Reserved health storage intentionally has no write API. A synthetic file proves
        // family reset/logout do not delete or overwrite this reserved file; no health data.
        File marker = new File(directory, "private_health.db");
        Files.write(marker.toPath(), "synthetic-health-retention-marker".getBytes(StandardCharsets.UTF_8));
        return marker;
    }

    @Test public void cacheAndEncryptedSessionPersistAcrossCloseReopen() throws Exception {
        family().cacheRemoteSnapshot(FamilyRepository.CacheKind.QUESTS, "persisted", "{\"z\":2,\"a\":{\"y\":1,\"b\":0}}");
        byte[] encrypted = Files.readAllBytes(sessionFile.toPath());
        assertEquals(1, encrypted[0]);
        assertTrue(encrypted.length > 29);
        String raw = new String(encrypted, StandardCharsets.ISO_8859_1);
        assertFalse(raw.contains(ACCESS));
        assertFalse(raw.contains(REFRESH));
        assertFalse(raw.contains("synthetic-user-a"));
        reopen();
        assertEquals(ACCESS, data.sessionStore().read().token);
        assertEquals(REFRESH, data.sessionStore().read().refreshToken);
        assertEquals("{\"a\":{\"b\":0,\"y\":1},\"z\":2}", family().cached(FamilyRepository.CacheKind.QUESTS, "persisted").canonicalPayload);
    }

    @Test public void queuePersistsStableIdCanonicalPayloadAndReconcileState() {
        PendingOperation created = family().enqueue(FamilyRepository.OperationKind.QUEST_CREATE,
                "{\"title\":\"fixture\",\"description\":\"synthetic\"}");
        assertEquals(created.requestId, UUID.fromString(created.requestId).toString());
        assertEquals("{\"description\":\"synthetic\",\"title\":\"fixture\"}", created.canonicalPayload);
        assertFalse(family().acknowledgeServerResult(created.requestId));
        reopen();
        PendingOperation queued = family().pending().get(0);
        assertEquals(created.requestId, queued.requestId);
        assertEquals(created.canonicalPayload, queued.canonicalPayload);
        assertEquals("queued", queued.status);
        assertTrue(family().markDispatched(created.requestId));
        assertFalse(family().markDispatched(created.requestId));
        assertFalse(family().markDispatched(UUID.randomUUID().toString()));
        reopen();
        PendingOperation retry = family().pending().get(0);
        assertEquals(created.requestId, retry.requestId);
        assertEquals(created.canonicalPayload, retry.canonicalPayload);
        assertEquals("sent_needs_reconcile", retry.status);
        assertTrue(retry.lastAttemptEpochMillis > 0);
        assertFalse(family().acknowledgeServerResult(UUID.randomUUID().toString()));
        assertEquals(1, family().pending().size());
        assertTrue(family().acknowledgeServerResult(created.requestId));
        assertFalse(family().acknowledgeServerResult(created.requestId));
        assertTrue(family().pending().isEmpty());
    }

    @Test public void allOperationKindsRejectHealthUnknownCredentialsAndNestedFields() {
        for (FamilyRepository.OperationKind kind : FamilyRepository.OperationKind.values()) {
            for (String field : Arrays.asList("health", "mood", "symptoms", "medication", "period", "access_token", "refresh_token", "unknown")) {
                rejects(IllegalArgumentException.class, () -> family().enqueue(kind, "{\"" + field + "\":\"synthetic\"}"));
            }
        }
        String[][] allowed = {
            {"QUEST_CREATE", "title"}, {"QUEST_UPDATE", "title"}, {"QUEST_SUBMIT", "occurrence_id"},
            {"REMINDER_SAVE", "title"}, {"APPEAL_SUBMIT", "reason"}, {"REWARD_REQUEST", "reward_id"}
        };
        for (String[] pair : allowed) {
            FamilyRepository.OperationKind kind = FamilyRepository.OperationKind.valueOf(pair[0]);
            rejects(IllegalArgumentException.class, () -> family().enqueue(kind, "{\"" + pair[1] + "\":{\"health\":\"synthetic\"}}"));
            rejects(IllegalArgumentException.class, () -> family().enqueue(kind, "{\"" + pair[1] + "\":[\"synthetic\"]}"));
        }
        assertTrue(family().pending().isEmpty());
    }

    @Test public void logoutClearsCacheQueueAndCredentialsRetainsHealthMarker() throws Exception {
        FamilyRepository old = family();
        addSnapshotAndIntent(old);
        File marker = healthMarker();
        byte[] before = Files.readAllBytes(marker.toPath());
        data.logout();
        assertNull(data.sessionStore().read());
        assertFalse(sessionFile.exists());
        rejects(IllegalStateException.class, old::pending);
        assertArrayEquals(before, Files.readAllBytes(marker.toPath()));
        data.activate(session("synthetic-user-a", ENDPOINT));
        assertTrue(family().pending().isEmpty());
        assertNull(family().cached(FamilyRepository.CacheKind.QUESTS, "synthetic-record"));
    }

    @Test public void accountSwitchClearsPreviousDataAndRejectsOldHandle() {
        FamilyRepository old = family();
        addSnapshotAndIntent(old);
        data.activate(session("synthetic-user-b", ENDPOINT));
        rejects(IllegalStateException.class, old::pending);
        rejects(IllegalStateException.class, () -> data.family("synthetic-user-a", ENDPOINT));
        FamilyRepository other = data.family("synthetic-user-b", ENDPOINT);
        assertTrue(other.pending().isEmpty());
        assertNull(other.cached(FamilyRepository.CacheKind.QUESTS, "synthetic-record"));
        data.activate(session("synthetic-user-a", ENDPOINT));
        assertTrue(family().pending().isEmpty());
        assertNull(family().cached(FamilyRepository.CacheKind.QUESTS, "synthetic-record"));
        rejects(IllegalStateException.class, old::pending);
    }

    @Test public void endpointSwitchClearsPreviousDataAndRejectsOldHandle() {
        FamilyRepository old = family();
        addSnapshotAndIntent(old);
        data.activate(session("synthetic-user-a", OTHER_ENDPOINT));
        rejects(IllegalStateException.class, old::pending);
        rejects(IllegalStateException.class, () -> data.family("synthetic-user-a", ENDPOINT));
        assertTrue(data.family("synthetic-user-a", OTHER_ENDPOINT).pending().isEmpty());
        assertNull(data.family("synthetic-user-a", OTHER_ENDPOINT).cached(FamilyRepository.CacheKind.QUESTS, "synthetic-record"));
        data.activate(session("synthetic-user-a", ENDPOINT));
        assertTrue(family().pending().isEmpty());
        assertNull(family().cached(FamilyRepository.CacheKind.QUESTS, "synthetic-record"));
        rejects(IllegalStateException.class, old::pending);
    }

    @Test public void logoutSameAccountReloginInvalidatesEveryOldHandleOperation() {
        FamilyRepository old = family();
        addSnapshotAndIntent(old);
        String id = old.pending().get(0).requestId;
        data.logout();
        data.activate(session("synthetic-user-a", ENDPOINT));
        rejects(IllegalStateException.class, old::pending);
        rejects(IllegalStateException.class, () -> old.cached(FamilyRepository.CacheKind.QUESTS, "synthetic-record"));
        rejects(IllegalStateException.class, () -> old.cacheRemoteSnapshot(FamilyRepository.CacheKind.QUESTS, "stale", "{}"));
        rejects(IllegalStateException.class, () -> old.enqueue(FamilyRepository.OperationKind.REWARD_REQUEST, "{\"reward_id\":\"synthetic\"}"));
        rejects(IllegalStateException.class, () -> old.markDispatched(id));
        rejects(IllegalStateException.class, () -> old.acknowledgeServerResult(id));
        assertTrue(family().pending().isEmpty());
    }

    @Test public void tokenRefreshPreservesExistingValidHandle() {
        FamilyRepository valid = family();
        addSnapshotAndIntent(valid);
        data.activate(new Session("synthetic-user-a", "https://VERIFICATION.invalid:443/",
                "synthetic-refreshed-access", "synthetic-refreshed-refresh", 4102444800L));
        assertEquals("synthetic-refreshed-access", data.sessionStore().read().token);
        assertEquals(1, valid.pending().size());
        assertNotNull(valid.cached(FamilyRepository.CacheKind.QUESTS, "synthetic-record"));
        assertTrue(valid.markDispatched(valid.pending().get(0).requestId));
    }

    @Test public void corruptSessionRequiresExplicitResetAndRetainsHealthMarker() throws Exception {
        FamilyRepository old = family();
        addSnapshotAndIntent(old);
        File marker = healthMarker();
        byte[] healthBefore = Files.readAllBytes(marker.toPath());
        byte[] corrupt = Files.readAllBytes(sessionFile.toPath());
        corrupt[corrupt.length - 1] ^= 1;
        Files.write(sessionFile.toPath(), corrupt);
        rejects(IllegalStateException.class, () -> data.sessionStore().read());
        rejects(IllegalStateException.class, old::pending);
        rejects(IllegalStateException.class, data::logout);
        rejects(IllegalStateException.class, () -> data.activate(session("synthetic-user-b", ENDPOINT)));
        assertArrayEquals(corrupt, Files.readAllBytes(sessionFile.toPath()));
        data.resetLocalFamilyAndSession();
        assertNull(data.sessionStore().read());
        assertArrayEquals(healthBefore, Files.readAllBytes(marker.toPath()));
        data.activate(session("synthetic-user-a", ENDPOINT));
        assertTrue(family().pending().isEmpty());
        assertNull(family().cached(FamilyRepository.CacheKind.QUESTS, "synthetic-record"));
        rejects(IllegalStateException.class, old::pending);
    }

    @Test public void atomicFileRecoversBackupWhenBaseIsAbsent() throws Exception {
        addSnapshotAndIntent(family());
        byte[] before = Files.readAllBytes(sessionFile.toPath());
        File backup = new File(sessionFile.getPath() + ".bak");
        Files.move(sessionFile.toPath(), backup.toPath());
        assertFalse(sessionFile.exists());
        reopen();
        assertEquals("synthetic-user-a", data.sessionStore().read().userId);
        assertArrayEquals(before, Files.readAllBytes(sessionFile.toPath()));
        assertFalse(backup.exists());
        assertEquals(1, family().pending().size());
        assertNotNull(family().cached(FamilyRepository.CacheKind.QUESTS, "synthetic-record"));
    }
}
