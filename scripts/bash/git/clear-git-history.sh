git checkout --orphan new-branch
git add -A
git commit -m "Initial commit"
git branch -D main
git branch -m main
git push -f origin main
git branch --set-upstream-to=origin main
