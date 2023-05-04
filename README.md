# K8S offline

Ce projet vise à simplifier le déploiement d'un cluster K8S dans un environnement air-gapped.

> **Remarques** :
> - Ça serait plus sexy avec ansible...
> - Ce projet n'a pas de grandes prétentions, d'autres le font bien mieux (ex : K3S, K0S, etc.).

> **Avis impopulaire** : K8S est un char d'assault surcôté. Dans 95+% des scénarios (et à fortiori dans un environnement offline !) Docker Swarm Mode ou Nomad (HashiCorp) sont amplement suffisants !

## Prérequis
- Debian 10+ (ou dérivé)
- `docker.io`, `rsync`, `apt-transport-https`, `ca-certificates`, `curl`, `gnupg2`, `software-properties-common`, `ethtool`, `ebtables`, `socat`, `conntrack`
  > Ces dépendances sont installées via `apt` dans `init.sh` et `join.sh`. Cela suppose l'existance d'un miroir apt (type apt-cacher) accessible et configuré. Si ce n'est pas le cas, il faudra les récupérer manuellement et les transférer sur les nodes du cluster K8S...

## Inforamtions
- Version K8S utilisée : 1.23.1
  > Pour upagrder vers une verion plus récente :
  > - remplacer les images docker (ou modifier les tags dans le script `download_images.sh`),
  > - remplacer les packages `.deb` (vérifier les compatibilités avec les images docker !)
  > - modifier la variable `${K8S_VERSION}` dans `init.sh`.

Ce déploiement utilise le plugin CNI **calico** pour faire du masquerading (e.g. : tous les flux sortent par l'@IP du node master).

Assurez-vous que le pool d'@IP de calico (`snat.yaml`) correspond à celui de la variable `${K8S_PODS_CIDR}` dans `init.sh` et qu'il ne soit pas en conflit avec votre réseau.

## Arborescence
- `calicoctl` : Binaire CLI pour controller le plugin CNI calico du cluster K8S
- `config` : Contient toutes les configs à déployer sur le cluster K8S après initialisation (essentiellement : privilèges, limitation de ressources, réseau et journalisation)
- `debs` : Contient les dépendances de K8S (paquets deb)
- `images` : Contient une archive compressée de toutes les images docker dont dépend K8S
- `scripts` : Contient des scripts permettant d'automatiser la mise en place (ou a minima de comprendre comment elle se déroule) du cluster K8S.

## Utilisation
- Cloner ce projet dans un répertoire sur tous les futurs noeuds du cluster K8S
- Sur une machine avec accès à internet :
  - Copier le script `scripts/download_images.sh` et l'éditer en fonction du besoin (notamment les versions des images)
  - Exécuter le script `scripts/download_images.sh`
  - Copier l'archive résultante (`images.tar.gz`) sur TOUS LES NOEUDS K8S (dans le répertoire `images` à la racine de ce projet : `images/images.tar.gz`)
- Sur le noeud MASTER :
  - Editer les fichiers yaml dans le répertoire `config` (notamment `config/cni/calico/snat.yaml` et `config/logging/fluentd.yaml`).
  - Editer le fichier `scripts/init.sh` pour modifier les variables (addresses IP, CIDR, rétention des images docker, etc.)
  - Exécuter le script `scripts/init.sh` en tant que superutilisateur
    - (exécuter `chmod +x scripts/init.sh` au préalable si besoin)
- Copier les fichiers `scripts/join_command` (créé après l'exécution de `scripts/init.sh`) et `scripts/admin.conf` du noeud MASTER vers le répertoire de ce projet sur les (futurs) noeuds WORKERS du cluster K8S.
- Sur les noeuds WORKERS :
  - Editer le fichier `scripts/join.sh` si besoin (notamment les variables)
  - Exécuter le script `scripts/join.sh` en tant que superutilisateur

Pour vérifier le bon foncitonnement du cluster, lancer la commande `kubectl get nodes` (en superutilisateur) : tous les noeuds doivent apparaître et être en état `Ready`.

GLHF 🙂
