# hello-world
This is my first repository.
This is the text associated with my first branch.
I wanted to change the capitaliation.
Here I wanted to add a line locally via the command line.

Here I am testing how branching works.
Adding my text here.  Wow!
And now I am testing it again with a new commit.  Will this new line be added?  How will it appear in GitHub?

To [change the default branch](https://dev.to/rhymu8354/git-renaming-the-master-branch-137b):
```bash
git clone <repository_URL>
cd <repository_dir>
git branch -m master main
git push -u origin main
# Change the default branch in repository page at GitHub.com, etc.
git push origin --delete master
git remote set-head origin -a
```


