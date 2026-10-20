import Foundation

/// The guide note and sample notes written into a new vault, in the interface language (English, French
/// or Spanish). File paths, property names and values, and the board's view names stay in English: they
/// are data the board and the app read.
extension StarterKit {
    /// "en", "fr" or "es": the app's interface language.
    static var starterLanguage: String {
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        let code = Locale(identifier: preferred).language.languageCode?.identifier ?? "en"
        return ["fr", "es"].contains(code) ? code : "en"
    }

    public static var guide: String {
        switch starterLanguage {
        case "fr": frenchGuide
        case "es": spanishGuide
        default: englishGuide
        }
    }

    /// Plain layout's "About these notes", in the interface language.
    public static var about: String {
        switch starterLanguage {
        case "fr": frenchAbout
        case "es": spanishAbout
        default: englishAbout
        }
    }

    static let englishAbout = """
        # About these notes

        Audio Pencil saves long recordings (and, if you turn it on, quick dictations) here as Markdown notes:

        - **Audio Pencil/Notes**, or the folder you set for a style: one note per recording.
        - **Audio Pencil/Recordings**: the audio of long recordings, linked from each note.
        - **Audio Pencil/Settings.md**: styles, vocabulary and tags, shared by your devices. You can edit it in any text editor.

        Each note starts with properties between `---` lines:

        | Property | What it means |
        | --- | --- |
        | `style` | How it was written up: `raw`, `polished`, `diary`, `professional` or your own styles. |
        | `status` | `needs-review`, `reviewed` or `actioned`. |
        | `recorded`, `duration` | When you started talking, and for how long (seconds). |
        | `language` | The language spoken. |
        | `tags` | From your tag list in Settings.md. |
        | `retention` | `regular` (audio kept a year), `archive` (kept forever) or `delete` (removed at the next check). Change it here or with Keep forever and Delete on the app's Notes page. |
        | `audio` | The recording, for long recordings. |

        This folder works with Obsidian too. If you open it as an Obsidian vault, Audio Pencil offers to add a review board.

        """

    static let frenchAbout = """
        # À propos de ces notes

        Audio Pencil enregistre ici les longs enregistrements (et, si vous l’activez, les dictées rapides) sous forme de notes Markdown :

        - **Audio Pencil/Notes**, ou le dossier choisi pour un style : une note par enregistrement.
        - **Audio Pencil/Recordings** : l’audio des longs enregistrements, lié depuis chaque note.
        - **Audio Pencil/Settings.md** : styles, vocabulaire et tags, partagés entre vos appareils. Modifiable dans n’importe quel éditeur de texte.

        Chaque note commence par des propriétés entre deux lignes `---` :

        | Propriété | Signification |
        | --- | --- |
        | `style` | La façon dont elle a été rédigée : `raw`, `polished`, `diary`, `professional` ou vos propres styles. |
        | `status` | `needs-review`, `reviewed` ou `actioned`. |
        | `recorded`, `duration` | Le moment où vous avez commencé à parler, et la durée (en secondes). |
        | `language` | La langue parlée. |
        | `tags` | Tirés de votre liste de tags dans Settings.md. |
        | `retention` | `regular` (audio gardé un an), `archive` (gardé pour toujours) ou `delete` (supprimé à la prochaine vérification). Modifiez-la ici ou avec Garder pour toujours et Supprimer dans la page Notes de l’app. |
        | `audio` | L’enregistrement, pour les longs enregistrements. |

        Ce dossier fonctionne aussi avec Obsidian. Si vous l’ouvrez comme coffre Obsidian, Audio Pencil propose d’ajouter un tableau de relecture.

        """

    static let spanishAbout = """
        # Sobre estas notas

        Audio Pencil guarda aquí las grabaciones largas (y, si lo activas, los dictados rápidos) como notas en Markdown:

        - **Audio Pencil/Notes**, o la carpeta que elijas para un estilo: una nota por grabación.
        - **Audio Pencil/Recordings**: el audio de las grabaciones largas, enlazado desde cada nota.
        - **Audio Pencil/Settings.md**: estilos, vocabulario y etiquetas, compartidos entre tus dispositivos. Puedes editarlo con cualquier editor de texto.

        Cada nota empieza con propiedades entre dos líneas `---`:

        | Propiedad | Qué significa |
        | --- | --- |
        | `style` | Cómo se redactó: `raw`, `polished`, `diary`, `professional` o tus propios estilos. |
        | `status` | `needs-review`, `reviewed` o `actioned`. |
        | `recorded`, `duration` | Cuándo empezaste a hablar y cuánto duró (segundos). |
        | `language` | El idioma hablado. |
        | `tags` | De tu lista de etiquetas en Settings.md. |
        | `retention` | `regular` (audio guardado un año), `archive` (para siempre) o `delete` (se borra en la siguiente comprobación). Cámbialo aquí o con Conservar siempre y Eliminar en la página Notas de la app. |
        | `audio` | La grabación, en las grabaciones largas. |

        Esta carpeta también funciona con Obsidian. Si la abres como bóveda de Obsidian, Audio Pencil te ofrecerá añadir un tablero de revisión.

        """

    static let frenchGuide = """
        ---
        type: audio-pencil-guide
        tags:
          - sample
        ---

        # Guide Audio Pencil

        Audio Pencil enregistre chaque enregistrement conservé sous forme de note avec les mêmes **propriétés** \
        (le bloc en haut de chaque note). Les Bases d'Obsidian transforment ces propriétés en tableau de relecture : \
        rien à classer à la main.

        ## Le tableau

        Ouvrez [[Audio Pencil/Audio Pencil.base|Audio Pencil.base]]. Ses vues (à choisir en haut à gauche) gardent \
        leur nom anglais :

        - **Professional review** : un tableau Kanban des notes Professional, une colonne par `status`. Faites glisser \
        une carte de *needs-review* vers *reviewed* une fois lue, puis vers *actioned* quand ses actions sont faites. \
        Le glisser-déposer modifie la propriété `status` de la note pour vous.
        - **Diary** : vos entrées de journal, les plus récentes en premier.
        - **All recordings** : tout, sous forme de tableau à trier et filtrer.
        - **Retention** : ce qu'il faut garder. Les notes *regular* gardent leur audio un an, puis l'audio est supprimé \
        (la note reste). *archive* garde la note et l'audio pour toujours. Faites glisser une carte vers *delete* et \
        Audio Pencil supprime la note et son audio (dans la corbeille) à la vérification suivante.

        ## Les propriétés

        | Propriété | Signification |
        | --- | --- |
        | `type` | Toujours `audio-pencil`, pour que le tableau trouve ces notes. |
        | `style` | La façon dont l'enregistrement a été rédigé : `raw`, `polished`, `diary`, `professional` ou vos propres styles. |
        | `status` | `needs-review` (nouvelle ou passée), `reviewed` ou `actioned`. |
        | `recorded` | Le moment où vous avez commencé à parler. |
        | `duration` | Durée de l'enregistrement en secondes. |
        | `device` | `mac` ou `iphone`. |
        | `mode` | `quick` (dictée au raccourci), `long-form` ou `meeting`. |
        | `language` | La langue parlée, par exemple `fr`. |
        | `tags` | Tirés de votre liste de tags dans `Audio Pencil/Settings.md`. |
        | `retention` | `regular` (audio gardé un an), `archive` (gardé pour toujours) ou `delete` (supprimé à la prochaine vérification). |
        | `audio` | Lien vers l'enregistrement dans `Audio Pencil/Recordings` (enregistrements longs uniquement). |

        ## Les statuts en pratique

        - Quand un long enregistrement est prêt, Audio Pencil vous demande d'approuver son titre, ses tags et son \
        dossier. **Approuver** l'enregistre en `reviewed` ; **Passer** l'enregistre en `needs-review`, et il vous \
        attend sur le tableau.
        - Parcourez la colonne *needs-review* quand vous avez un moment : rien ne se perd.
        - Utilisez *actioned* pour les notes Professional dont vous avez fait les actions.

        ## Exemples

        Les notes de [[Audio Pencil/Samples]] sont des exemples (tag `sample`, vous pouvez les supprimer) :

        - une entrée de journal : vos mots, mis au propre ;
        - une note Professional avec ses actions et la transcription d'origine repliée en dessous ;
        - une note encore en *needs-review*.

        ## Réglages

        Les styles, le vocabulaire et la liste de tags se trouvent dans [[Audio Pencil/Settings|Settings]]. \
        Modifiez-les là ou dans l'app : les deux restent synchronisés.

        """

    static let spanishGuide = """
        ---
        type: audio-pencil-guide
        tags:
          - sample
        ---

        # Guía de Audio Pencil

        Audio Pencil guarda cada grabación como una nota con las mismas **propiedades** (el bloque al principio de \
        cada nota). Las Bases de Obsidian convierten esas propiedades en un tablero de revisión, así que no hay \
        que archivar nada a mano.

        ## El tablero

        Abre [[Audio Pencil/Audio Pencil.base|Audio Pencil.base]]. Sus vistas (se eligen arriba a la izquierda) \
        mantienen el nombre en inglés:

        - **Professional review**: un tablero Kanban de las notas Professional, una columna por `status`. Arrastra \
        una tarjeta de *needs-review* a *reviewed* cuando la hayas leído, y a *actioned* cuando hayas hecho sus \
        tareas. Al arrastrarla, la propiedad `status` de la nota cambia sola.
        - **Diary**: tus entradas de diario, las más recientes primero.
        - **All recordings**: todo, en una tabla que puedes ordenar y filtrar.
        - **Retention**: qué conservar. Las notas *regular* guardan su audio un año y luego se elimina el audio (la \
        nota se queda). *archive* conserva la nota y el audio para siempre. Arrastra una tarjeta a *delete* y Audio \
        Pencil borra la nota y su audio (a la papelera) en la siguiente comprobación.

        ## Las propiedades

        | Propiedad | Qué significa |
        | --- | --- |
        | `type` | Siempre `audio-pencil`, para que el tablero encuentre estas notas. |
        | `style` | Cómo se redactó la grabación: `raw`, `polished`, `diary`, `professional` o tus propios estilos. |
        | `status` | `needs-review` (nueva u omitida), `reviewed` o `actioned`. |
        | `recorded` | Cuándo empezaste a hablar. |
        | `duration` | Duración de la grabación en segundos. |
        | `device` | `mac` o `iphone`. |
        | `mode` | `quick` (dictado con el atajo), `long-form` o `meeting`. |
        | `language` | El idioma hablado, por ejemplo `es`. |
        | `tags` | De tu lista de etiquetas en `Audio Pencil/Settings.md`. |
        | `retention` | `regular` (audio guardado un año), `archive` (para siempre) o `delete` (se borra en la siguiente comprobación). |
        | `audio` | Enlace a la grabación en `Audio Pencil/Recordings` (solo grabaciones largas). |

        ## Los estados en la práctica

        - Cuando termina una grabación larga, Audio Pencil te pide aprobar su título, etiquetas y carpeta. \
        **Aprobar** la guarda como `reviewed`; **Omitir** la guarda como `needs-review` y te espera en el tablero.
        - Repasa la columna *needs-review* cuando tengas un momento; no se pierde nada.
        - Usa *actioned* para las notas Professional cuyas tareas ya hayas hecho.

        ## Ejemplos

        Las notas de [[Audio Pencil/Samples]] son ejemplos (con la etiqueta `sample`; puedes borrarlas):

        - una entrada de diario: tus palabras, ordenadas;
        - una nota Professional con tareas y la transcripción original plegada debajo;
        - una nota todavía en *needs-review*.

        ## Ajustes

        Los estilos, el vocabulario y la lista de etiquetas están en [[Audio Pencil/Settings|Settings]]. Edítalos \
        ahí o en la app; los dos se mantienen sincronizados.

        """
}

/// The sample notes' words, per language.
struct SampleText {
    var language: String
    var diaryTitle: String
    var diaryBody: String
    var professionalTitle: String
    var professionalBody: String
    var professionalTranscript: String
    var reviewTitle: String
    var reviewBody: String
    var reviewTranscript: String

    static var current: SampleText {
        switch StarterKit.starterLanguage {
        case "fr": french
        case "es": spanish
        default: english
        }
    }

    static let english = SampleText(
        language: "en",
        diaryTitle: "Sample: a good day with a run along the river",
        diaryBody: """
            Today was actually a pretty good day. I got up early and went for a run along the river, which I \
            hadn't done in two weeks, and it felt really good.

            Work was mostly meetings. The server migration finally finished, so that's a weight off. In the \
            afternoon I picked up the kids and we made pizza, and Maya put way too much cheese on hers, which \
            was funny.

            I'm a bit tired now, but in a good way. I want to keep the running going, maybe three times a week.
            """,
        professionalTitle: "Sample: backup plan for the home server",
        professionalBody: """
            The home server is backed up nightly to a drive in the same room, which won't survive a fire. \
            I'm choosing between a drive swapped at my parents' place, encrypted backups to the Nextcloud box \
            at the cottage, or paid cloud storage, and leaning towards the cottage because it's automatic.

            **Key points**
            - Current backups share a room with the server: no protection from fire or theft.
            - Cottage upload is about 10 Mbps, so the first sync could take a week.
            - I've never tested a restore.

            **Action items**
            - [ ] Set up the cottage sync this weekend.
            - [ ] Ask Dave whether the cottage router can have a static IP.
            - [ ] Test-restore the photos folder next week.
            """,
        professionalTranscript: """
            So I've been thinking about the backup situation for the home server. Right now everything goes to, \
            uh, the external drive every night, and that's fine, but it's in the same room, so if there's a fire \
            or whatever, it's all gone. I'm leaning towards the cottage because it's automatic, but the upload \
            there is slow, like ten megabits, so the first sync would take, I don't know, a week maybe. I should \
            test restoring too, I've never actually restored anything, which is bad.
            """,
        reviewTitle: "Sample: ideas for the quarterly planning",
        reviewBody: """
            For the quarter we should focus on three things: finishing the backup migration, shipping the new \
            onboarding flow, and hiring a second support person before the summer.

            **Key points**
            - Backup migration is the risk to clear first.
            - Onboarding changes depend on the new sign-up page.
            - Support load justifies a second hire.
            """,
        reviewTranscript: "So for the quarterly planning, I think we should focus on three things…"
    )

    static let french = SampleText(
        language: "fr",
        diaryTitle: "Exemple : une bonne journée avec un footing au bord de la rivière",
        diaryBody: """
            Au fond, aujourd'hui a été une plutôt bonne journée. Je me suis levé tôt et je suis allé courir au \
            bord de la rivière, ce que je n'avais pas fait depuis deux semaines, et ça m'a fait vraiment du bien.

            Le travail, c'était surtout des réunions. La migration du serveur est enfin terminée, ça m'enlève un \
            poids. L'après-midi, j'ai récupéré les enfants et on a fait des pizzas ; Maya a mis beaucoup trop de \
            fromage sur la sienne, c'était drôle.

            Je suis un peu fatigué maintenant, mais dans le bon sens. J'aimerais continuer à courir, peut-être \
            trois fois par semaine.
            """,
        professionalTitle: "Exemple : plan de sauvegarde du serveur de la maison",
        professionalBody: """
            Le serveur de la maison est sauvegardé chaque nuit sur un disque dans la même pièce, ce qui ne \
            résisterait pas à un incendie. J'hésite entre un disque échangé chez mes parents, des sauvegardes \
            chiffrées vers le Nextcloud du chalet ou un stockage cloud payant, et je penche pour le chalet parce \
            que c'est automatique.

            **Points clés**
            - Les sauvegardes actuelles sont dans la même pièce que le serveur : aucune protection contre le feu ou le vol.
            - L'envoi depuis le chalet plafonne à environ 10 Mbit/s, donc la première synchronisation pourrait prendre une semaine.
            - Je n'ai jamais testé de restauration.

            **Actions**
            - [ ] Mettre en place la synchronisation avec le chalet ce week-end.
            - [ ] Demander à Dave si le routeur du chalet peut avoir une IP fixe.
            - [ ] Tester la restauration du dossier photos la semaine prochaine.
            """,
        professionalTranscript: """
            Bon, j'ai réfléchi à la question des sauvegardes du serveur de la maison. Pour l'instant tout part, \
            euh, sur le disque externe chaque nuit, et ça va, mais il est dans la même pièce, donc s'il y a un \
            incendie ou quoi, tout est perdu. Je penche pour le chalet parce que c'est automatique, mais l'envoi \
            là-bas est lent, genre dix mégabits, donc la première synchro prendrait, je sais pas, une semaine \
            peut-être. Je devrais aussi tester une restauration, je n'ai jamais rien restauré, ce qui n'est pas bien.
            """,
        reviewTitle: "Exemple : idées pour la planification du trimestre",
        reviewBody: """
            Ce trimestre, on devrait se concentrer sur trois choses : terminer la migration des sauvegardes, \
            livrer le nouveau parcours d'accueil et recruter une deuxième personne au support avant l'été.

            **Points clés**
            - La migration des sauvegardes est le risque à lever en premier.
            - Les changements de l'accueil dépendent de la nouvelle page d'inscription.
            - La charge du support justifie un deuxième recrutement.
            """,
        reviewTranscript: "Bon, pour la planification du trimestre, je pense qu'on devrait se concentrer sur trois choses…"
    )

    static let spanish = SampleText(
        language: "es",
        diaryTitle: "Ejemplo: un buen día con una carrera junto al río",
        diaryBody: """
            La verdad es que hoy ha sido un día bastante bueno. Me levanté temprano y salí a correr junto al río, \
            cosa que no hacía desde hacía dos semanas, y me sentó muy bien.

            El trabajo fue sobre todo reuniones. Por fin terminó la migración del servidor, así que me quito un \
            peso de encima. Por la tarde recogí a los niños e hicimos pizza; Maya le puso demasiado queso a la \
            suya, y fue muy gracioso.

            Ahora estoy un poco cansado, pero de buena manera. Quiero seguir corriendo, quizá tres veces por semana.
            """,
        professionalTitle: "Ejemplo: plan de copias de seguridad del servidor de casa",
        professionalBody: """
            El servidor de casa se copia cada noche en un disco que está en la misma habitación, y eso no \
            sobreviviría a un incendio. Dudo entre un disco que se intercambia en casa de mis padres, copias \
            cifradas al Nextcloud de la casa de campo o almacenamiento en la nube de pago, y me inclino por la \
            casa de campo porque es automático.

            **Puntos clave**
            - Las copias actuales están en la misma habitación que el servidor: no protegen de un incendio ni de un robo.
            - La subida en la casa de campo es de unos 10 Mbps, así que la primera sincronización podría tardar una semana.
            - Nunca he probado a restaurar.

            **Tareas**
            - [ ] Configurar la sincronización con la casa de campo este fin de semana.
            - [ ] Preguntar a Dave si el router de la casa de campo puede tener una IP fija.
            - [ ] Probar a restaurar la carpeta de fotos la semana que viene.
            """,
        professionalTranscript: """
            Bueno, he estado pensando en lo de las copias de seguridad del servidor de casa. Ahora mismo todo va, \
            eh, al disco externo cada noche, y está bien, pero está en la misma habitación, así que si hay un \
            incendio o lo que sea, se pierde todo. Me inclino por la casa de campo porque es automático, pero la \
            subida allí es lenta, como de diez megas, así que la primera sincronización tardaría, no sé, una \
            semana quizá. También debería probar a restaurar, nunca he restaurado nada, y eso no está bien.
            """,
        reviewTitle: "Ejemplo: ideas para la planificación del trimestre",
        reviewBody: """
            Este trimestre deberíamos centrarnos en tres cosas: terminar la migración de las copias de \
            seguridad, lanzar el nuevo proceso de bienvenida y contratar a una segunda persona de soporte antes \
            del verano.

            **Puntos clave**
            - La migración de las copias es el primer riesgo que hay que despejar.
            - Los cambios de la bienvenida dependen de la nueva página de registro.
            - La carga de soporte justifica una segunda contratación.
            """,
        reviewTranscript: "Bueno, para la planificación del trimestre, creo que deberíamos centrarnos en tres cosas…"
    )
}
