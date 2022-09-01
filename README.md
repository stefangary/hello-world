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

This is wonderful.  Now, I'm making changes so I can test pushing a commit with SSH authentication. Thanks to [Martin V. Loewis](https://stackoverflow.com/questions/4565700/how-to-specify-the-private-ssh-key-to-use-when-executing-shell-command-on-git)
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

Great!  That worked.  Now I'm going to test pushing another commit
on a different machine (via PAT) and then pulling that update to
yet another machine (via SSH). So, first edit, then do the usual
```bash
# On a different computer
git add .
git commit
git push origin
```

And then, on the first computer where I have the repo already and tried SSH auth:
```bash
# Should not work due to [this issue](https://stackoverflow.com/questions/52379234/git-gnutls-handshake-failed-error-in-the-pull-function)
git pull

# Should work
ssh-agent bash -c 'ssh-add /gs/gsfs0/users/gstefan/pw/workflows/tmp_id; git pull
```
