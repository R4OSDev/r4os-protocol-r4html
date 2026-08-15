R4HTML
======

R4HTML.R4P stellt den wiederverwendbaren HTML-Dokumentkern unter der Rolle
`application.html` bereit. Der eigentliche Parser liegt als gemeinsam
verwendbarer Userland-Code in `r4os.html`.

Operationen:

1 - Faehigkeiten abfragen
2 - HTML parsen und begrenzte Dokumentstatistik ausgeben
3 - HTML als einfache Text-/Ueberschriften-/Listenansicht ausgeben
4 - deterministischer Parser-, DOM-, Encoding-, Modus-, MIME- und
    Darstellungs-Selbsttest

Jedes Dokument besitzt seine dekodierten Bytes, DOM-Knoten, Attribute und
Texte selbst. Feste Grenzen fuer Quelle, Knoten, Attribute, Tiefe und
Darstellung liefern sichtbare Fehler statt unkontrollierten Speicherwuchs.
Die zustandslosen R4P-Komfortoperationen serialisieren ihren gemeinsamen
Arbeitspuffer und melden parallele Belegung sichtbar als `busy`.
UTF-8 und Windows-1252 werden unter Beachtung von BOM, HTTP-Content-Type und
frueher Meta-Charset-Angabe verarbeitet.

`text/html` wird dem HTML-Handler zugeordnet, `text/plain` bleibt ein
Klartextdokument und unbekannte Typen werden nicht still als HTML
interpretiert. Ein moderner HTML-DOCTYPE aktiviert Standardsmodus; bekannte
Transitional-/Frameset-DOCTYPEs aktivieren Limited Quirks, fehlende oder
fremde Deklarationen Quirks.

R4HTML liegt weder im Kernel noch in R4DRAW. R4CSS und `r4os.web_layout`
bilden CSS und Layout als getrennte Userland-Schicht. `r4os.web_forms`
besitzt Formularzustand und Ereigniswarteschlange; JavaScript bleibt
ebenfalls getrennt.
