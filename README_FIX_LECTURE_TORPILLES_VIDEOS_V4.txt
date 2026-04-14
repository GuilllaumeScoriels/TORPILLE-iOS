Correctif lecture des torpilles vidéos

Ce correctif rend la lecture plus robuste :
- les nouvelles vidéos enregistrent désormais aussi videoUrl dans Firestore
- la lecture essaie d'abord la Cloud Function videoSignedUrl
- si elle échoue, l'application bascule automatiquement vers Firebase Storage downloadURL

Fichiers modifiés :
- TorpilleIOS/Models/Models.swift
- TorpilleIOS/Repositories/Services.swift
- TorpilleIOS/Repositories/Repositories.swift
- TorpilleIOS/ViewModels/ViewModels.swift
