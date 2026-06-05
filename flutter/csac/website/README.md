# CsAC Website

Static React + Material 3 website for the Flutter CsAC client.

## Development

```powershell
npm install
npm run dev
```

## Build

```powershell
npm run build
```

The site has no backend. Recent changelog data is loaded in the browser from the
GitHub Releases API, with a local fallback when GitHub cannot be reached.
