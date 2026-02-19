# Git Setup Script for TAGER ERP
# Run this script to initialize the repository and push to GitHub

Write-Host "🚀 Starting Git Setup..." -ForegroundColor Cyan

# 1. Initialize Git
if (-not (Test-Path ".git")) {
    Write-Host "Initializing Git repository..."
    git init
    git branch -m main
} else {
    Write-Host "Git repository already initialized."
}

# 2. Add all files
Write-Host "Adding files..."
git add .

# 3. Commit
Write-Host "Committing files..."
git commit -m "feat: initial monorepo setup with turborepo and supabase schema"

# 4. Prompt for Remote URL
$remoteUrl = Read-Host "Enter your GitHub Repository URL (e.g., https://github.com/username/tager-erp.git)"

if ($remoteUrl) {
    # Remove existing origin if present
    git remote remove origin 2>$null
    
    # Add new origin
    git remote add origin $remoteUrl
    
    # Push
    Write-Host "Pushing to GitHub..."
    git push -u origin main
    
    Write-Host "✅ Successfully pushed to GitHub!" -ForegroundColor Green
} else {
    Write-Host "⚠️ No URL provided. You can run 'git remote add origin <url>' and 'git push' later." -ForegroundColor Yellow
}

Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
