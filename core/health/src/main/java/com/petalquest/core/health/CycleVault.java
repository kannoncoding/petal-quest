package com.petalquest.core.health;

import android.content.Context;
import android.os.Build;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.AtomicFile;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.SecureRandom;
import java.text.SimpleDateFormat;
import java.util.*;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/** Device-local authenticated vault. All operations share this instance's monitor.
 * Keep one instance per application; never persist snapshots or export without explicit consent. */
public final class CycleVault {
    private static final String ALIAS = "petalquest.privatecycle.wrap.v1";
    private static final byte[] HEADER = new byte[]{80,81,67,86,1};
    private final AtomicFile vault, wrapped;
    private byte[] dataKey;
    private Snapshot state;
    private long generation;

    public static final class VaultException extends Exception {
        public VaultException(String message, Throwable cause) { super(message, cause); }
    }
    public static final class Period {
        public final String id, startDate, endDate;
        public Period(String id, String startDate, String endDate) {
            this.id=id; this.startDate=startDate; this.endDate=endDate;
        }
        public int inclusiveLength() { return endDate == null ? 0 : days(startDate,endDate)+1; }
    }
    public static final class Observation {
        public final String date, flow, consistency, painLocation, notes;
        public final Integer pain;
        public final List<String> symptoms;
        public Observation(String date,String flow,String consistency,Integer pain,String painLocation,List<String> symptoms,String notes) {
            this.date=date; this.flow=flow; this.consistency=consistency; this.pain=pain;
            this.painLocation=painLocation; this.notes=notes;
            this.symptoms=Collections.unmodifiableList(new ArrayList<>(symptoms == null ? Collections.emptyList() : symptoms));
        }
    }
    public static final class Snapshot {
        public final List<Period> periods;
        public final List<Observation> observations;
        private Snapshot(List<Period> p,List<Observation> o) {
            periods=Collections.unmodifiableList(new ArrayList<>(p)); observations=Collections.unmodifiableList(new ArrayList<>(o));
        }
    }
    public CycleVault(Context context) {
        File dir=new File(context.getApplicationContext().getNoBackupFilesDir(),"private_cycle");
        vault=new AtomicFile(new File(dir,"vault.enc")); wrapped=new AtomicFile(new File(dir,"key.enc"));
    }
    private KeyStore store() throws Exception { KeyStore s=KeyStore.getInstance("AndroidKeyStore"); s.load(null); return s; }
    private boolean exists(AtomicFile f) { return f.getBaseFile().exists() || new File(f.getBaseFile()+".bak").exists(); }
    /** Creates only the authentication-bound wrapping key. Call before opening the OS prompt. */
    public synchronized void prepareKey() throws VaultException {
        try {
            KeyStore s=store();
            if (s.containsAlias(ALIAS)) return;
            if(exists(vault)||exists(wrapped)) throw new IOException("Missing existing wrapping key");
            KeyGenerator g=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");
            KeyGenParameterSpec.Builder b=new KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT)
                    .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setUserAuthenticationRequired(true);
            if(Build.VERSION.SDK_INT>=30) b.setUserAuthenticationParameters(30,KeyProperties.AUTH_BIOMETRIC_STRONG|KeyProperties.AUTH_DEVICE_CREDENTIAL);
            else b.setUserAuthenticationValidityDurationSeconds(30);
            g.init(b.build()); g.generateKey();
        } catch(Exception e) { throw failure(e); }
    }
    /** Must be called only following successful OS authentication, including for an empty vault. */
    public synchronized long unlockAfterAuthentication() throws VaultException {
        lock();
        byte[] candidate=null;
        try {
            SecretKey wrapping=(SecretKey)store().getKey(ALIAS,null);
            if(wrapping==null) throw new IOException("Key unavailable");
            Snapshot loaded;
            if(exists(wrapped)) {
                candidate=decrypt(wrapping,wrapped.readFully());
                if(candidate.length!=32 || !exists(vault)) throw new IOException("Incomplete vault");
                byte[] plain=decrypt(new SecretKeySpec(candidate,"AES"),vault.readFully());
                try { loaded=decode(new String(plain,StandardCharsets.UTF_8)); } finally { Arrays.fill(plain,(byte)0); }
            } else {
                if(exists(vault)) throw new IOException("Missing data key");
                candidate=new byte[32]; new SecureRandom().nextBytes(candidate);
                // Wrapping is itself authentication-bound, so no plaintext is made available before auth.
                write(wrapped,encrypt(wrapping,candidate));
                loaded=new Snapshot(Collections.emptyList(),Collections.emptyList());
                persist(candidate,loaded);
            }
            dataKey=candidate; candidate=null; state=loaded; return generation;
        } catch(Exception e) { throw failure(e); }
        finally { if(candidate!=null) Arrays.fill(candidate,(byte)0); }
    }
    public synchronized void lock() { if(dataKey!=null) Arrays.fill(dataKey,(byte)0); dataKey=null; state=null; generation++; }
    public synchronized boolean isUnlocked() { return dataKey!=null; }
    public synchronized long generation() { return generation; }
    public synchronized Snapshot snapshot() { require(generation); return new Snapshot(state.periods,state.observations); }
    private void require(long token) { if(dataKey==null||token!=generation) throw new IllegalStateException("Unlock the private cycle journal again."); }
    public synchronized void savePeriod(long token,Period p) throws VaultException {
        require(token); List<Period> list=new ArrayList<>(state.periods); list.removeIf(x->x.id.equals(p.id)); list.add(p);
        commit(new Snapshot(list,state.observations));
    }
    public synchronized void deletePeriod(long token,String id) throws VaultException {
        require(token); List<Period> list=new ArrayList<>(state.periods); list.removeIf(x->x.id.equals(id)); commit(new Snapshot(list,state.observations));
    }
    public synchronized void saveObservation(long token,Observation o) throws VaultException {
        require(token); List<Observation> list=new ArrayList<>(state.observations); list.removeIf(x->x.date.equals(o.date)); list.add(o); commit(new Snapshot(state.periods,list));
    }
    public synchronized void deleteObservation(long token,String date) throws VaultException {
        require(token); List<Observation> list=new ArrayList<>(state.observations); list.removeIf(x->x.date.equals(date)); commit(new Snapshot(state.periods,list));
    }
    public String exportEncrypted(long token,char[] passphrase) throws VaultException {
        byte[] plain=null,key=null; PBEKeySpec spec=null;
        try {
            synchronized(this) { require(token); }
            if(passphrase==null||passphrase.length<12) throw new IllegalArgumentException("Use at least 12 characters for the backup password.");
            byte[] salt=new byte[16]; new SecureRandom().nextBytes(salt);
            String kdf=Build.VERSION.SDK_INT>=26?"PBKDF2WithHmacSHA256":"PBKDF2WithHmacSHA1";
            int iterations=Build.VERSION.SDK_INT>=26?600000:1000000;
            spec=new PBEKeySpec(passphrase,salt,iterations,256);
            key=SecretKeyFactory.getInstance(kdf).generateSecret(spec).getEncoded();
            JSONObject metadata=new JSONObject().put("format","petalquest-cycle-backup").put("version",1).put("kdf",kdf).put("iterations",iterations).put("salt",android.util.Base64.encodeToString(salt,android.util.Base64.NO_WRAP));
            // The exact UTF-8 metadata string is authenticated; do not reserialize it for restore.
            String aad=metadata.toString(); Cipher c=Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(key,"AES")); c.updateAAD(aad.getBytes(StandardCharsets.UTF_8));
            synchronized(this) {
                require(token);
                plain=encode(state).toString().getBytes(StandardCharsets.UTF_8);
                return new JSONObject().put("metadata",aad).put("iv",android.util.Base64.encodeToString(c.getIV(),android.util.Base64.NO_WRAP)).put("ciphertext",android.util.Base64.encodeToString(c.doFinal(plain),android.util.Base64.NO_WRAP)).toString();
            }
        } catch(IllegalArgumentException|IllegalStateException e) { throw e; }
        catch(Exception e) { throw new VaultException("The encrypted backup could not be created.",e); }
        finally { if(passphrase!=null) Arrays.fill(passphrase,'\0'); if(spec!=null) spec.clearPassword(); if(key!=null) Arrays.fill(key,(byte)0); if(plain!=null) Arrays.fill(plain,(byte)0); }
    }
    /** UI must obtain explicit destructive confirmation first. Does not touch any family data. */
    public synchronized void resetConfirmed() throws VaultException {
        lock(); try { vault.delete(); wrapped.delete(); store().deleteEntry(ALIAS);
            if(exists(vault)||exists(wrapped)) throw new IOException("Deletion incomplete");
        } catch(Exception e) { throw failure(e); }
    }
    private void commit(Snapshot next) throws VaultException {
        validate(next); try { persist(dataKey,next); state=next; } catch(Exception e) { lock(); throw failure(e); }
    }
    private void persist(byte[] key,Snapshot s) throws Exception {
        byte[] plain=encode(s).toString().getBytes(StandardCharsets.UTF_8);
        try { write(vault,encrypt(new SecretKeySpec(key,"AES"),plain)); } finally { Arrays.fill(plain,(byte)0); }
    }
    private static byte[] encrypt(SecretKey key,byte[] plain) throws Exception {
        Cipher c=Cipher.getInstance("AES/GCM/NoPadding"); c.init(Cipher.ENCRYPT_MODE,key); c.updateAAD(HEADER);
        byte[] iv=c.getIV(), body=c.doFinal(plain);
        ByteArrayOutputStream out=new ByteArrayOutputStream(); out.write(HEADER); out.write(iv.length); out.write(iv); out.write(body); return out.toByteArray();
    }
    private static byte[] decrypt(SecretKey key,byte[] value) throws Exception {
        if(value.length<HEADER.length+1+12+16 || !Arrays.equals(HEADER,Arrays.copyOf(value,HEADER.length)) || value[HEADER.length]!=12) throw new IOException("Invalid vault envelope");
        Cipher c=Cipher.getInstance("AES/GCM/NoPadding"); c.init(Cipher.DECRYPT_MODE,key,new GCMParameterSpec(128,value,HEADER.length+1,12)); c.updateAAD(HEADER);
        return c.doFinal(value,HEADER.length+13,value.length-HEADER.length-13);
    }
    private static void write(AtomicFile file,byte[] bytes) throws IOException {
        File dir=file.getBaseFile().getParentFile(); if(!dir.isDirectory()&&!dir.mkdirs()) throw new IOException("Storage unavailable");
        FileOutputStream out=null;
        try { out=file.startWrite(); out.write(bytes); file.finishWrite(out); }
        catch(IOException e) { if(out!=null) file.failWrite(out); throw e; }
    }
    private static VaultException failure(Exception e) { return new VaultException("The private journal could not be opened or saved. Unlock again. If the device key was lost, only an earlier export can recover entries; reset deletes this journal.",e); }
    public static String today() { return format().format(new Date()); }
    private static SimpleDateFormat format() { SimpleDateFormat f=new SimpleDateFormat("yyyy-MM-dd",Locale.US); f.setTimeZone(TimeZone.getTimeZone("America/Costa_Rica")); f.setLenient(false); return f; }
    private static Date date(String value) {
        if(value==null||!value.matches("\\d{4}-\\d{2}-\\d{2}")) throw new IllegalArgumentException("Use a valid date.");
        try { Date d=format().parse(value); if(!format().format(d).equals(value)) throw new IllegalArgumentException("Use a valid date."); return d; } catch(java.text.ParseException e) { throw new IllegalArgumentException("Use a valid date."); }
    }
    private static void past(String v) { date(v); if(v.compareTo(today())>0) throw new IllegalArgumentException("Dates cannot be in the future."); }
    public static int days(String a,String b) {
        GregorianCalendar start=new GregorianCalendar(TimeZone.getTimeZone("UTC")); GregorianCalendar end=new GregorianCalendar(TimeZone.getTimeZone("UTC"));
        String[] x=a.split("-"),y=b.split("-"); start.clear(); end.clear(); start.set(Integer.parseInt(x[0]),Integer.parseInt(x[1])-1,Integer.parseInt(x[2])); end.set(Integer.parseInt(y[0]),Integer.parseInt(y[1])-1,Integer.parseInt(y[2])); return (int)((end.getTimeInMillis()-start.getTimeInMillis())/86400000L);
    }
    private static void validate(Snapshot s) {
        Set<String> ids=new HashSet<>(), dates=new HashSet<>();
        for(Period p:s.periods) {
            try { if(!UUID.fromString(p.id).toString().equals(p.id)) throw new Exception(); } catch(Exception e) { throw new IllegalArgumentException("Period id must be a UUID."); }
            if(!ids.add(p.id)) throw new IllegalArgumentException("Duplicate period."); past(p.startDate); if(p.endDate!=null) { past(p.endDate); if(p.endDate.compareTo(p.startDate)<0) throw new IllegalArgumentException("End date must follow start date."); }
        }
        for(int i=0;i<s.periods.size();i++) for(int j=i+1;j<s.periods.size();j++) {
            Period a=s.periods.get(i),b=s.periods.get(j); String ae=a.endDate==null?today():a.endDate,be=b.endDate==null?today():b.endDate;
            if(a.startDate.compareTo(be)<=0&&b.startDate.compareTo(ae)<=0) throw new IllegalArgumentException("Periods cannot overlap.");
        }
        for(Observation o:s.observations) { past(o.date); if(!dates.add(o.date)) throw new IllegalArgumentException("Duplicate daily observation.");
            if(o.flow!=null&&!o.flow.isEmpty()&&!Arrays.asList("light","moderate","heavy","spotting").contains(o.flow)) throw new IllegalArgumentException("Choose a valid subjective flow.");
            if(o.pain!=null&&(o.pain<0||o.pain>10)) throw new IllegalArgumentException("Pain must be between 0 and 10.");
            for(String symptom:o.symptoms) if(symptom==null) throw new IllegalArgumentException("Invalid symptom.");
        }
    }
    private static JSONObject encode(Snapshot s) throws Exception {
        JSONArray ps=new JSONArray(),os=new JSONArray();
        for(Period p:s.periods) ps.put(new JSONObject().put("id",p.id).put("startDate",p.startDate).put("endDate",p.endDate==null?JSONObject.NULL:p.endDate));
        for(Observation o:s.observations) os.put(new JSONObject().put("date",o.date).put("flow",nullable(o.flow)).put("consistency",nullable(o.consistency)).put("pain",o.pain==null?JSONObject.NULL:o.pain).put("painLocation",nullable(o.painLocation)).put("symptoms",new JSONArray(o.symptoms)).put("notes",nullable(o.notes)));
        return new JSONObject().put("version",1).put("periods",ps).put("observations",os);
    }
    private static Object nullable(String s) { return s==null?JSONObject.NULL:s; }
    private static String optional(JSONObject o,String k) throws Exception { return o.isNull(k)?null:o.getString(k); }
    private static Snapshot decode(String json) throws Exception {
        JSONObject root=new JSONObject(json); if(root.getInt("version")!=1) throw new IOException("Unknown vault version");
        List<Period> ps=new ArrayList<>(); List<Observation> os=new ArrayList<>(); JSONArray pa=root.getJSONArray("periods"),oa=root.getJSONArray("observations");
        for(int i=0;i<pa.length();i++) { JSONObject p=pa.getJSONObject(i); ps.add(new Period(p.getString("id"),p.getString("startDate"),optional(p,"endDate"))); }
        for(int i=0;i<oa.length();i++) { JSONObject o=oa.getJSONObject(i); List<String> symptoms=new ArrayList<>(); JSONArray a=o.getJSONArray("symptoms"); for(int j=0;j<a.length();j++) symptoms.add(a.getString(j)); os.add(new Observation(o.getString("date"),optional(o,"flow"),optional(o,"consistency"),o.isNull("pain")?null:o.getInt("pain"),optional(o,"painLocation"),symptoms,optional(o,"notes"))); }
        Snapshot s=new Snapshot(ps,os); validate(s); return s;
    }
}
