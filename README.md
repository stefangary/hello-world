# hello-world
This is my first repository.
This is the text associated with my first branch.
I wanted to change the capitaliation.
Here I wanted to add a line locally via the command line.

Here I am testing how branching works.
Adding my text here.  Wow!
And now I am testing it again with a new commit.  Will this new line be added?  How will it appear in GitHub?

To [change the default branch](https://dev.to/rhymu8354/git-renaming-the-master-branch-137b), thanks to rhymu8354:
```bash
git clone <repository_URL>
cd <repository_dir>
git branch -m master main
git push -u origin main
# Change the default branch in repository page at GitHub.com, etc.
git push origin --delete master
git remote set-head origin -a
```

This is wonderful.  Now, I'm making changes so I can test pushing a commit with SSH authentication.
I was able to clone the repository with:
```bash
ssh-agent bash -c 'ssh-add /gs/gsfs0/users/gstefan/pw/workflows/tmp_id; git clone git@github.com:stefangary/hello-world.git'
```
and now I'm going to do:
```bash
git add .
git commit
ssh-agent bash -c 'ssh-add /gs/gsfs0/users/gstefan/pw/workflows/tmp_id; git push origin'
```
