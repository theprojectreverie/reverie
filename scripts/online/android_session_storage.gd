extends RefCounted
## Encrypt only the rotating refresh credential using an Android Keystore
## AES-GCM key. Never save the password or an unencrypted fallback.
const KEY_ALIAS := "reverie_session_aes_v3"

static func _java():
 return Engine.get_singleton("JavaClassWrapper")

static func _key(create: bool):
 var java = _java()
 if java == null:return null
 var ks_class = java.wrap("java.security.KeyStore")
 var store = ks_class.getInstance("AndroidKeyStore")
 if store == null:return null
 store.load(null)
 if java.get_exception()!=null:return null
 if store.containsAlias(KEY_ALIAS):
  return store.getKey(KEY_ALIAS,null)
 if not create:return null
 var builder_class = java.wrap("android.security.keystore.KeyGenParameterSpec$Builder")
 var builder = builder_class.new(KEY_ALIAS,3)
 builder.setBlockModes(PackedStringArray(["GCM"]))
 builder.setEncryptionPaddings(PackedStringArray(["NoPadding"]))
 builder.setKeySize(256)
 var spec = builder.build()
 if java.get_exception()!=null or spec==null:return null
 var generator = java.wrap("javax.crypto.KeyGenerator").getInstance("AES","AndroidKeyStore")
 if generator==null:return null
 generator.init(spec)
 if java.get_exception()!=null:return null
 return generator.generateKey()

static func write_token(path: String,token: String) -> bool:
 var java = _java()
 var key = _key(true)
 if key==null:return false
 var cipher = java.wrap("javax.crypto.Cipher").getInstance("AES/GCM/NoPadding")
 if cipher==null:return false
 cipher.init(1,key)
 if java.get_exception()!=null:return false
 var encrypted = cipher.doFinal(token.to_utf8_buffer())
 var iv = cipher.getIV()
 if java.get_exception()!=null or not encrypted is PackedByteArray or not iv is PackedByteArray or iv.size()!=12:return false
 var payload := JSON.stringify({"iv":Marshalls.raw_to_base64(iv),"ciphertext":Marshalls.raw_to_base64(encrypted)})
 var f := FileAccess.open(path+".tmp",FileAccess.WRITE)
 if f==null:return false
 f.store_string(payload)
 f.flush()
 f.close()
 return DirAccess.rename_absolute(path+".tmp",path)==OK

static func read_token(path: String) -> String:
 var java = _java()
 var key = _key(false)
 if key==null:return ""
 var data = JSON.parse_string(FileAccess.get_file_as_string(path))
 if not data is Dictionary:return ""
 var iv := Marshalls.base64_to_raw(str(data.get("iv","")))
 var encrypted := Marshalls.base64_to_raw(str(data.get("ciphertext","")))
 if iv.size()!=12 or encrypted.size()<32 or encrypted.size()>512:return ""
 var params = java.wrap("javax.crypto.spec.GCMParameterSpec").new(128,iv)
 var cipher = java.wrap("javax.crypto.Cipher").getInstance("AES/GCM/NoPadding")
 if params==null or cipher==null:return ""
 cipher.init(2,key,params)
 if java.get_exception()!=null:return ""
 var decoded = cipher.doFinal(encrypted)
 if java.get_exception()!=null or not decoded is PackedByteArray:return ""
 var token: String=decoded.get_string_from_utf8()
 return token if token.length()>=32 and token.length()<=200 else ""