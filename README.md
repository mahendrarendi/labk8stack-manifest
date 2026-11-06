# LabK8stack Helm deployment

Chart ini memasang aplikasi LabK8stack. Cluster PostgreSQL CloudNativePG
(CNPG) boleh berada di namespace yang sama atau berbeda. Operator CNPG
dipasang terpisah di `cnpg-system`; cluster database dan Secret koneksi harus
siap sebelum chart aplikasi dipasang. Chart ini tidak membuat PostgreSQL,
StorageClass, PVC, atau Secret aplikasi.

## Sebelum memasang

1. Pasang operator CNPG dengan versi chart yang dipilih dan dipin.
2. Buat CNPG `Cluster` di namespace database yang dipilih, beserta backup yang
   teruji.
3. Jika CNPG berada dalam namespace aplikasi, gunakan Secret
   `<cluster-name>-app` dengan key `uri`. Jika beda namespace, buat atau sinkronkan
   Secret koneksi **di namespace aplikasi** dan isi URI dengan host lengkap,
   seperti `<cluster-name>-rw.<db-namespace>.svc.cluster.local`. Kubernetes
   tidak mengizinkan Pod merujuk Secret dari namespace lain.
4. Push image aplikasi LabK8stack dan image challenge ke registry.
5. Buat Secret aplikasi berisi `SECRET_KEY` acak, `LAB_APP_IMAGE`, dan
   `LAB_APP_GOOD_TAGS`. Simpan Secret melalui pengelola Secret cluster Anda;
   jangan commit nilai rahasia ke Git.

Nilai yang wajib diisi: `image.repository`, `image.tag`,
`database.clusterName`, dan `app.configSecretName`. Lihat [values.yaml](values.yaml).
Untuk namespace database berbeda, isi juga `database.namespace` dan
`database.appSecretName` (nama Secret lokal di namespace aplikasi).

```bash
helm lint . \
  --set image.repository=REGISTRY/labk8stack \
  --set image.tag=TAG \
  --set database.clusterName=labk8stack-db \
  --set app.configSecretName=labk8stack-config

helm upgrade --install labk8stack . \
  --namespace labk8stack --create-namespace --wait \
  --set image.repository=REGISTRY/labk8stack \
  --set image.tag=TAG \
  --set database.clusterName=labk8stack-db \
  --set app.configSecretName=labk8stack-config
```

Contoh bila CNPG berada di namespace `labk8stack-db`:

```bash
helm upgrade --install labk8stack . \
  --namespace labk8stack --create-namespace --wait \
  --set image.repository=REGISTRY/labk8stack \
  --set image.tag=TAG \
  --set database.namespace=labk8stack-db \
  --set database.clusterName=labk8stack-db \
  --set database.appSecretName=labk8stack-db-connection \
  --set app.configSecretName=labk8stack-config
```

Secret `labk8stack-db-connection` harus ada di namespace `labk8stack`, berisi
key `uri` yang menunjuk Service `labk8stack-db-rw.labk8stack-db.svc.cluster.local`.
Jangan menyalin URI CNPG tanpa memeriksa host-nya: nama Service pendek akan
dicari di namespace aplikasi. Gunakan pengelola Secret agar rotasi kredensial
tetap dapat dilakukan.

Untuk rilis sungguhan, simpan nilai non-rahasia dalam file values lingkungan
dan pin image dengan tag immutable atau digest. `ingress.enabled` default
`false`; saat diaktifkan, isi host, class, dan TLS Secret. Cookie sesi memakai
atribut `Secure` sehingga akses browser harus melalui HTTPS.

Chart menjalankan Job migrasi database sebelum web dirilis, memasang satu
replica aplikasi, menjalankan CronJob cleanup tiap 15 menit, dan memasang
NetworkPolicy ingress untuk Pod CNPG hanya bila CNPG satu namespace dengan
aplikasi. Policy tersebut mengizinkan aplikasi, sesama Pod CNPG, serta operator
di `database.operatorNamespace` pada port yang dibutuhkan. Untuk namespace
database terpisah, kelola NetworkPolicy CNPG bersama release database dan
izinkan trafik dari Pod aplikasi ke port 5432. Namespace challenge dibuat
oleh aplikasi dengan NetworkPolicy ingress/egress sendiri; trafik keluar
dibatasi ke Pod satu namespace dan DNS `kube-system`.

Periksa kembali label/namespace operator, jaringan CNI, StorageClass, dan
jadwal backup sebelum menerapkan chart ke cluster. ClusterRole provisioner
memiliki izin cluster-wide untuk membuat dan menghapus namespace lab; gunakan
cluster khusus atau kebijakan admission tambahan bila platform dibuka untuk
pengguna yang tidak dipercaya.
