## Obtenir une liste des cours à demander à M. Marroy

echo Writing liste_des_cours.txt
grep -v '^ *#\|^ *$' repartition.txt  | cut -d\; -f 2 | sed 's|/.*||' | sort -u > liste_des_cours.txt

## Comparer avec ce que j'ai reçu et placé dans sciences.txt

if [ -f sciences.txt ]; then 
    echo Writing liste_recue.txt and comparing.
    csvcut -d , -f 3 sciences.txt |
        tail -n +2 |
        sed s#/Global## |
        sed 's# \+$##' |
        sort -u > liste_recue.txt
    
    diff -u liste_des_cours.txt liste_recue.txt
else
    echo No sciences.txt to compare with.
fi
