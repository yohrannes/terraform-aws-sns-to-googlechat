data "aws_region" "current" {}
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${var.alert_name}.zip"
  source_dir  = "${path.root}/lambda_function"
}

resource "aws_iam_role" "lambda_alert_role" {
  name = "${var.alert_name}-alert-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.alert_name}alert-role"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_alert_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "alert_function" {
  filename         = "${var.alert_name}.zip"
  function_name    = "function_${var.alert_name}"
  role            = aws_iam_role.lambda_alert_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = 60

provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.root}/lambda_function
      cd ${path.root}/lambda_function
      wget https://bootstrap.pypa.io/get-pip.py
      python3 get-pip.py
      pip install requests -t .
      cat > lambda_function.py << 'EOF'
import json
import os
import requests
from datetime import datetime

def enviar_mensagem_google_chat(texto):
    """
    Envia mensagem para o Google Chat via webhook
    
    Args:
        texto (str): Mensagem a ser enviada
        
    Returns:
        str: Confirmação do envio
        
    Raises:
        ValueError: Se webhook URL não estiver configurado
        Exception: Se houver erro no envio
    """
    webhook_url = os.environ.get("GOOGLE_CHAT_WEBHOOK_URL")
    if not webhook_url:
        raise ValueError("Variável de ambiente GOOGLE_CHAT_WEBHOOK_URL não encontrada")
    
    payload = {"text": texto}
    
    response = requests.post(
        webhook_url,
        data=json.dumps(payload),
        headers={"Content-Type": "application/json"},
        timeout=10
    )
    
    if response.status_code != 200:
        raise Exception(f"Erro ao enviar mensagem para Google Chat: {response.status_code} - {response.text}")
    
    return "Mensagem enviada com sucesso para Google Chat"

def processar_mensagem_sns(sns_message):
    """
    Processa mensagem recebida do SNS Topic
    
    Args:
        sns_message (str or dict): Mensagem do SNS
        
    Returns:
        dict: Dados estruturados da mensagem
    """
    try:
        # Converter string JSON para dict se necessário
        if isinstance(sns_message, str):
            message_data = json.loads(sns_message)
        else:
            message_data = sns_message
            
        return message_data
        
    except json.JSONDecodeError as e:
        print(f"Erro ao decodificar JSON da mensagem SNS: {e}")
        # Retorna mensagem como texto simples se não for JSON válido
        return {"message": str(sns_message), "type": "text"}
    except Exception as e:
        print(f"Erro ao processar mensagem SNS: {e}")
        raise

def formatar_mensagem_para_chat(message_data, sns_subject="", topic_arn=""):
    """
    Formata mensagem do SNS para envio ao Google Chat
    
    Args:
        message_data (dict): Dados da mensagem
        sns_subject (str): Subject do SNS
        topic_arn (str): ARN do tópico SNS
        
    Returns:
        str: Mensagem formatada para Google Chat
    """
    timestamp = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
    
    # Cabeçalho da mensagem
    mensagem = "📨 *MENSAGEM RECEBIDA VIA SNS*\n\n"
    
    # Subject se disponível
    if sns_subject:
        mensagem += f"📋 Assunto: {sns_subject}\n"
    
    # Se for uma mensagem estruturada (JSON)
    if isinstance(message_data, dict) and "message" not in message_data:
        for key, value in message_data.items():
            # Formatar chaves para exibição mais amigável
            key_formatado = key.replace("_", " ").replace("-", " ").title()
            mensagem += f"{key_formatado}: {value}\n"
    else:
        # Mensagem simples ou texto
        conteudo = message_data.get("message", str(message_data))
        mensagem += f"💬 Conteúdo:\n```\n{conteudo}\n```\n"
    
    # Informações do SNS
    if topic_arn:
        # Extrair nome do tópico do ARN
        topic_name = topic_arn.split(":")[-1] if ":" in topic_arn else topic_arn
        mensagem += f"🏷️ Tópico SNS: {topic_name}\n"
    
    mensagem += f"🕐 Recebido em: {timestamp}\n"
    mensagem += f"\n---\n*Mensagem processada automaticamente*"
    
    return mensagem

def lambda_handler(event, context):
    """
    Função principal do Lambda
    Recebe eventos do SNS Topic e repassa para Google Chat
    
    Args:
        event (dict): Evento do AWS Lambda
        context (object): Contexto do AWS Lambda
        
    Returns:
        dict: Response com status da execução
    """
    try:
        # Log do evento para debugging
        print(f"Evento recebido: {json.dumps(event, indent=2, default=str)}")
        
        # Verificar se é um evento SNS válido
        if "Records" not in event:
            raise ValueError("Evento não possui 'Records'. Certifique-se de que está sendo chamado via SNS Topic.")
        
        records = event.get("Records", [])
        if not records:
            raise ValueError("Nenhum record encontrado no evento")
        
        resultados = []
        
        # Processar cada record do SNS
        for i, record in enumerate(records):
            print(f"Processando record {i + 1}/{len(records)}")
            
            # Verificar se é um record SNS
            if "Sns" not in record:
                print(f"Record {i + 1} não é do SNS, ignorando...")
                continue
            
            sns_data = record["Sns"]
            
            # Extrair dados do SNS
            sns_message = sns_data.get("Message", "")
            sns_subject = sns_data.get("Subject", "")
            topic_arn = sns_data.get("TopicArn", "")
            message_id = sns_data.get("MessageId", "")
            
            print(f"Processando mensagem SNS ID: {message_id}")
            print(f"Subject: {sns_subject}")
            print(f"Topic: {topic_arn}")
            
            # Processar mensagem
            message_data = processar_mensagem_sns(sns_message)
            
            # Formatar para Google Chat
            mensagem_formatada = formatar_mensagem_para_chat(
                message_data, 
                sns_subject, 
                topic_arn
            )
            
            # Enviar para Google Chat
            resultado_envio = enviar_mensagem_google_chat(mensagem_formatada)
            
            resultados.append({
                "message_id": message_id,
                "status": "sucesso",
                "resultado": resultado_envio
            })
            
            print(f"Mensagem {message_id} processada com sucesso")
        
        # Response de sucesso
        return {
            "statusCode": 200,
            "body": json.dumps({
                "status": "sucesso",
                "messages_processed": len(resultados),
                "results": resultados
            }, ensure_ascii=False)
        }
        
    except Exception as e:
        error_message = str(e)
        print(f"Erro na função Lambda: {error_message}")
        
        # Tentar notificar erro no Google Chat
        try:
            mensagem_erro = (
                "❌ *ERRO NO PROCESSAMENTO SNS*\n\n"
                f"Erro: {error_message}\n"
                f"Timestamp: {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}\n"
                "Função: Lambda SNS to Google Chat Bridge"
            )
            enviar_mensagem_google_chat(mensagem_erro)
            print("Notificação de erro enviada para Google Chat")
        except Exception as chat_error:
            print(f"Não foi possível enviar erro para Google Chat: {chat_error}")
        
        # Response de erro
        return {
            "statusCode": 500,
            "body": json.dumps({
                "status": "erro",
                "error": error_message,
                "event_received": event
            }, ensure_ascii=False)
        }
EOF
    EOT
  }

  environment {
    variables = {
      GOOGLE_CHAT_WEBHOOK_URL = var.gchat_webhook_url
    }
  }

  tags = {
    Name = "${var.alert_name}"
  }
}
