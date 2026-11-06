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

Nilai yang wajib diisi: `image.repository`, `image.tag` atau `image.digest`,
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

## GitOps dengan Argo CD

`environments/development/values.yaml` dan `environments/production/values.yaml`
menyimpan perbedaan yang tidak rahasia: image, nama database, namespace,
dan prefix namespace challenge. Development memakai prefix `lab-dev-u`,
production memakai `lab-prod-u`, agar resource kedua stage tidak bertabrakan.

`argocd/` berisi satu `AppProject` dan dua `Application`. Sebelum diterapkan:

1. Ganti `repoURL` dengan URL repository manifest yang sesungguhnya.
2. Isi `image.repository` dan `image.tag` atau `image.digest` dengan image yang
   sudah tersedia. Production sebaiknya menunjuk tag rilis atau digest
   yang sudah lulus pengujian, bukan `main`.
3. Sesuaikan namespace CNPG, nama cluster, Secret koneksi lokal, Ingress/TLS,
   serta namespace operator sesuai instalasi Anda.
4. Siapkan Secret di namespace aplikasi dan database, kemudian pastikan
   database sehat. Aplikasi development dan production tidak boleh memakai
   database yang sama.
5. Terapkan `argocd/project.yaml`, lalu kedua `Application`. `CreateNamespace`
   membuat namespace aplikasi saat sync; Secret dan CNPG tetap harus tersedia
   sebelum sync aplikasi.

Contoh validasi sebelum membuat `Application`:

```bash
helm lint . -f environments/development/values.yaml
helm template labk8stack-dev . -n labk8stack-dev \
  -f environments/development/values.yaml > /tmp/labk8stack-dev.yaml

helm lint . -f environments/production/values.yaml
helm template labk8stack . -n labk8stack \
  -f environments/production/values.yaml > /tmp/labk8stack-prod.yaml
```

Argo CD tidak menjalankan `helm install`; ia merender chart dengan Helm lalu
mengelola resource Kubernetes. Job migrasi yang memakai hook Helm dipetakan
menjadi `PreSync`. Dua `Application` sengaja tidak mengaktifkan `automated`,
`prune`, atau `selfHeal`; perubahan Git akan terlihat sebagai `OutOfSync` sampai
Anda memilih sync manual atau mengubah kebijakannya nanti. Jangan menjalankan
`helm upgrade` untuk release aplikasi yang sama setelah Argo CD menjadi
pengelolanya.
