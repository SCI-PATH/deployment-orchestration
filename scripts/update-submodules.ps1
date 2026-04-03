Write-Host "Updating all submodules..." -ForegroundColor Cyan

git submodule sync --recursive
git submodule update --init --recursive
git submodule update --remote --merge

Write-Host "Submodules updated successfully." -ForegroundColor Green
git status