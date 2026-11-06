# LabK8stack Helm deployment

Chart ini memasang aplikasi LabK8stack ke namespace yang sama dengan cluster
PostgreSQL CloudNativePG (CNPG). Operator CNPG dipasang terpisah di
`cnpg-system`; cluster database dan Secret `<cluster-name>-app` harus sudah
siap sebelum chart aplikasi dipasang. Chart ini tidak membuat PostgreSQL,
StorageClass, PVC, atau Secret aplikasi.

## Sebelum memasang

1. Pasang operator CNPG dengan versi chart yang dipilih dan dipin.
2. Buat CNPG `Cluster` di namespace `labk8stack`, beserta backup yang teruji.
3. Pastikan Secret `<cluster-name>-app` berisi key `uri` dan Service
   `<cluster-name>-rw` dapat diakses dari namespace yang sama.
4. Push image aplikasi LabK8stack dan image challenge ke registry.
5. Buat Secret aplikasi berisi `SECRET_KEY` acak, `LAB_APP_IMAGE`, dan
   `LAB_APP_GOOD_TAGS`. Simpan Secret melalui pengelola Secret cluster Anda;
   jangan commit nilai rahasia ke Git.

Nilai yang wajib diisi: `image.repository`, `image.tag`,
`database.clusterName`, dan `app.configSecretName`. Lihat [values.yaml](values.yaml).

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

Untuk rilis sungguhan, simpan nilai non-rahasia dalam file values lingkungan
dan pin image dengan tag immutable atau digest. `ingress.enabled` default
`false`; saat diaktifkan, isi host, class, dan TLS Secret. Cookie sesi memakai
atribut `Secure` sehingga akses browser harus melalui HTTPS.

Chart menjalankan Job migrasi database sebelum web dirilis, memasang satu
replica aplikasi, menjalankan CronJob cleanup tiap 15 menit, dan memasang
NetworkPolicy ingress untuk Pod CNPG. Policy tersebut mengizinkan aplikasi,
sesama Pod CNPG, serta operator di `database.operatorNamespace` pada port yang
dibutuhkan. Namespace challenge dibuat oleh aplikasi dengan NetworkPolicy
ingress/egress sendiri; trafik keluar dibatasi ke Pod satu namespace dan DNS
`kube-system`.

Periksa kembali label/namespace operator, jaringan CNI, StorageClass, dan
jadwal backup sebelum menerapkan chart ke cluster. ClusterRole provisioner
memiliki izin cluster-wide untuk membuat dan menghapus namespace lab; gunakan
cluster khusus atau kebijakan admission tambahan bila platform dibuka untuk
pengguna yang tidak dipercaya.
