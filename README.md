# ansible-openvas
scripts ansible pour automatiser l'installation openvas


Mise à jour des scap et cert data :
rsync -ltvrP --delete --exclude scap.db --exclude private/ rsync://feed.openvas.org:/scap-data ./scap-data
rsync -ltvrP --delete --exclude cert.db --exclude private/ rsync://feed.openvas.org:/cert-data ./cert-data

TODO : récupération du nvt-data
