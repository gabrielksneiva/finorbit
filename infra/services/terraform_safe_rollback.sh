#!/bin/bash
set -e

# Filtrar recursos que não têm a tag keep=true
non_critical_resources=$(terraform state list | while read resource; do
    keep=$(terraform state show "$resource" | grep -E 'keep\s*=\s*"true"')
    if [ -z "$keep" ]; then
        echo "$resource"
    fi
done)

if [ -z "$non_critical_resources" ]; then
    echo "Nenhum recurso não crítico para destruir."
    exit 0
fi

echo "Recursos não críticos a serem destruídos:"
echo "$non_critical_resources"

# Destruir apenas os não críticos
for res in $non_critical_resources; do
    terraform destroy -target="$res" -auto-approve
done
echo "Destruição segura concluída."